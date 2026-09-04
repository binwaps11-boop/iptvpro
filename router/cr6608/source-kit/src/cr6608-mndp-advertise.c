#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <limits.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define MNDP_PORT 5678
#define PACKET_CAPACITY 1400
#define FIELDS_MAX_BYTES 4096
#define MNDP_RECEIVE_DRAIN_LIMIT 64
#define RESCUE_IPV4_HOST UINT32_C(0xdddddddd) /* 221.221.221.221 */

static const char build_provenance[] = "cr6608-mndp-source-v4";

struct neighbor_fields {
    char identity[256];
    char platform[128];
    char version[128];
    char board[128];
    bool enabled;
    unsigned interval;
};

static volatile sig_atomic_t keep_running = 1;

static void stop_handler(int signo)
{
    (void)signo;
    keep_running = 0;
}

static bool component_name_valid(const char *name)
{
    const unsigned char *p = (const unsigned char *)name;

    if (!name || !*name || !strcmp(name, ".") || !strcmp(name, ".."))
        return false;
    for (; *p; p++) {
        if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
            (*p >= '0' && *p <= '9') || *p == '_' || *p == '-' || *p == '.')
            continue;
        return false;
    }
    return true;
}

static bool text_valid(const char *value)
{
    const unsigned char *p = (const unsigned char *)value;

    for (; *p; p++) {
        if (*p < 0x20 || *p == 0x7f)
            return false;
    }
    return true;
}

static int read_line(FILE *stream, char *out, size_t out_len)
{
    size_t len;

    if (!fgets(out, (int)out_len, stream))
        return -1;
    len = strlen(out);
    if (len && out[len - 1] == '\n')
        out[--len] = '\0';
    else if (!feof(stream))
        return -1;
    if (len && out[len - 1] == '\r')
        out[--len] = '\0';
    return text_valid(out) ? 0 : -1;
}

static int read_fields(const char *path, struct neighbor_fields *fields)
{
    struct stat st;
    char enabled[8], interval[16];
    char *end = NULL;
    long parsed;
    int fd, extra, stream_error;
    FILE *stream;

    fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0)
        return -1;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != geteuid() ||
        (st.st_mode & 0077) != 0 || st.st_nlink != 1 ||
        st.st_size < 6 || st.st_size > FIELDS_MAX_BYTES) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    stream = fdopen(fd, "r");
    if (!stream) {
        close(fd);
        return -1;
    }
    memset(fields, 0, sizeof(*fields));
    if (read_line(stream, fields->identity, sizeof(fields->identity)) ||
        read_line(stream, fields->platform, sizeof(fields->platform)) ||
        read_line(stream, fields->version, sizeof(fields->version)) ||
        read_line(stream, fields->board, sizeof(fields->board)) ||
        read_line(stream, enabled, sizeof(enabled)) ||
        read_line(stream, interval, sizeof(interval))) {
        fclose(stream);
        errno = EINVAL;
        return -1;
    }
    extra = fgetc(stream);
    stream_error = ferror(stream);
    if (fclose(stream) || extra != EOF || stream_error) {
        errno = EINVAL;
        return -1;
    }
    if (!fields->identity[0] || !fields->platform[0] ||
        !fields->version[0] || !fields->board[0] ||
        (strcmp(enabled, "0") && strcmp(enabled, "1"))) {
        errno = EINVAL;
        return -1;
    }
    errno = 0;
    parsed = strtol(interval, &end, 10);
    if (errno || !end || *end || parsed < 10 || parsed > 300) {
        errno = EINVAL;
        return -1;
    }
    fields->enabled = enabled[0] == '1';
    fields->interval = (unsigned)parsed;
    return 0;
}

static void put_be16(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)(value >> 8);
    out[1] = (uint8_t)value;
}

static uint16_t internet_checksum(const uint8_t *data, size_t length)
{
    uint32_t sum = 0;
    size_t offset;

    for (offset = 0; offset + 1 < length; offset += 2) {
        sum += ((uint32_t)data[offset] << 8) | data[offset + 1];
        sum = (sum & 0xffffU) + (sum >> 16);
    }
    if (offset < length)
        sum += (uint32_t)data[offset] << 8;
    while (sum >> 16)
        sum = (sum & 0xffffU) + (sum >> 16);
    return (uint16_t)~sum;
}

static int append_tlv(uint8_t *packet, size_t *used, uint16_t type,
                      const void *value, size_t value_len)
{
    if (value_len > UINT16_MAX || *used > PACKET_CAPACITY - 4 ||
        value_len > PACKET_CAPACITY - *used - 4) {
        errno = EOVERFLOW;
        return -1;
    }
    put_be16(packet + *used, type);
    put_be16(packet + *used + 2, (uint16_t)value_len);
    memcpy(packet + *used + 4, value, value_len);
    *used += value_len + 4;
    return 0;
}

static int build_packet(uint8_t *packet, size_t *packet_len,
                        const struct neighbor_fields *fields,
                        const uint8_t mac[6], struct in_addr ipv4,
                        const char *interface_name, uint32_t uptime)
{
    static const char software[] = "SmartAP";
    uint8_t uptime_le[4];
    size_t used = 4;

    memset(packet, 0, PACKET_CAPACITY);
    packet[0] = 0x00;
    packet[1] = 0x01;
    packet[2] = 0x00;
    packet[3] = 0x00;
    uptime_le[0] = (uint8_t)uptime;
    uptime_le[1] = (uint8_t)(uptime >> 8);
    uptime_le[2] = (uint8_t)(uptime >> 16);
    uptime_le[3] = (uint8_t)(uptime >> 24);

    if (append_tlv(packet, &used, 1, mac, 6) ||
        append_tlv(packet, &used, 5, fields->identity,
                   strlen(fields->identity)) ||
        append_tlv(packet, &used, 7, fields->version,
                   strlen(fields->version)) ||
        append_tlv(packet, &used, 8, fields->platform,
                   strlen(fields->platform)) ||
        append_tlv(packet, &used, 12, fields->board,
                   strlen(fields->board)) ||
        append_tlv(packet, &used, 10, uptime_le, sizeof(uptime_le)) ||
        append_tlv(packet, &used, 11, software, sizeof(software) - 1) ||
        append_tlv(packet, &used, 16, interface_name,
                   strlen(interface_name)) ||
        append_tlv(packet, &used, 17, &ipv4.s_addr, sizeof(ipv4.s_addr)))
        return -1;

    /* The deployed CR6608 sender uses bytes 2-3 as an RFC 1071-style
     * one's-complement checksum, despite some MNDP dissectors labelling this
     * word as a sequence.  Preserve that product wire contract exactly. */
    put_be16(packet + 2, internet_checksum(packet, used));
    *packet_len = used;
    return 0;
}

static bool interface_is_lan_bridge(const char *name)
{
    return !strcmp(name, "br-lan") || !strncmp(name, "br-lan.", 7);
}

static bool source_address_advertisable(struct in_addr address)
{
    /* The fail-closed rescue endpoint is deliberately bound to the same
     * bridge/VLAN as the management AP.  It is not a general management
     * address and must not create a duplicate RouterOS neighbor entry. */
    return ntohl(address.s_addr) != RESCUE_IPV4_HOST;
}

static int interface_mac(int control_socket, const char *name, uint8_t mac[6])
{
    struct ifreq request;

    memset(&request, 0, sizeof(request));
    if (strlen(name) >= sizeof(request.ifr_name)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(request.ifr_name, name);
    if (ioctl(control_socket, SIOCGIFHWADDR, &request) ||
        request.ifr_hwaddr.sa_family != ARPHRD_ETHER)
        return -1;
    memcpy(mac, request.ifr_hwaddr.sa_data, 6);
    if ((mac[0] & 1) || !(mac[0] | mac[1] | mac[2] | mac[3] | mac[4] | mac[5])) {
        errno = EADDRNOTAVAIL;
        return -1;
    }
    return 0;
}

static int open_sender_socket(void)
{
    struct sockaddr_in local;
    int one = 1;
    int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);

    if (fd < 0)
        return -1;
    if (setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof(one)) ||
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) ||
        setsockopt(fd, IPPROTO_IP, IP_PKTINFO, &one, sizeof(one))) {
        close(fd);
        return -1;
    }
    memset(&local, 0, sizeof(local));
    local.sin_family = AF_INET;
    local.sin_port = htons(MNDP_PORT);
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&local, sizeof(local))) {
        close(fd);
        return -1;
    }
    return fd;
}

/*
 * MNDP requires UDP source port 5678, so the sender must bind that port even
 * though it never consumes neighbor advertisements.  Linux consequently
 * queues local/peer broadcasts for this socket.  Drain a bounded batch without
 * blocking so normal traffic cannot fill SO_RCVBUF forever and a hostile LAN
 * cannot turn cleanup into an unbounded CPU loop.
 */
static int drain_received_datagrams(int sender, unsigned *drained_out)
{
    uint8_t discard[PACKET_CAPACITY];
    unsigned drained = 0;

    while (drained < MNDP_RECEIVE_DRAIN_LIMIT) {
        ssize_t received = recv(sender, discard, sizeof(discard), MSG_DONTWAIT);

        if (received >= 0) {
            drained++;
            continue;
        }
        if (errno == EINTR)
            continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            break;
        if (drained_out)
            *drained_out = drained;
        return -1;
    }
    if (drained_out)
        *drained_out = drained;
    return 0;
}

static bool drain_or_reopen_sender(int *sender)
{
    if (*sender < 0)
        *sender = open_sender_socket();
    if (*sender < 0)
        return false;
    if (drain_received_datagrams(*sender, NULL)) {
        close(*sender);
        *sender = open_sender_socket();
    }
    return *sender >= 0;
}

static int send_packet_on_interface(int sender, const uint8_t *packet,
                                    size_t packet_len, unsigned ifindex,
                                    struct in_addr source)
{
    struct sockaddr_in destination;
    struct in_pktinfo *packet_info;
    struct iovec vector;
    struct msghdr message;
    struct cmsghdr *control;
    char control_buffer[CMSG_SPACE(sizeof(struct in_pktinfo))];

    memset(&destination, 0, sizeof(destination));
    destination.sin_family = AF_INET;
    destination.sin_port = htons(MNDP_PORT);
    destination.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    memset(&message, 0, sizeof(message));
    memset(control_buffer, 0, sizeof(control_buffer));
    vector.iov_base = (void *)packet;
    vector.iov_len = packet_len;
    message.msg_name = &destination;
    message.msg_namelen = sizeof(destination);
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control_buffer;
    message.msg_controllen = sizeof(control_buffer);
    control = CMSG_FIRSTHDR(&message);
    control->cmsg_level = IPPROTO_IP;
    control->cmsg_type = IP_PKTINFO;
    control->cmsg_len = CMSG_LEN(sizeof(struct in_pktinfo));
    packet_info = (struct in_pktinfo *)CMSG_DATA(control);
    memset(packet_info, 0, sizeof(*packet_info));
    packet_info->ipi_ifindex = (int)ifindex;
    packet_info->ipi_spec_dst = source;

    return sendmsg(sender, &message, MSG_NOSIGNAL) == (ssize_t)packet_len ? 0 : -1;
}

static unsigned send_round(int sender, const struct neighbor_fields *fields,
                           uint32_t uptime)
{
    struct ifaddrs *interfaces = NULL, *entry;
    unsigned sent = 0;
    int control_socket = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);

    if (control_socket < 0 || getifaddrs(&interfaces)) {
        if (control_socket >= 0)
            close(control_socket);
        return 0;
    }
    for (entry = interfaces; entry; entry = entry->ifa_next) {
        struct sockaddr_in *address;
        uint8_t packet[PACKET_CAPACITY], mac[6];
        size_t packet_len = 0;
        unsigned ifindex;

        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET ||
            !(entry->ifa_flags & IFF_UP) ||
            !interface_is_lan_bridge(entry->ifa_name))
            continue;
        address = (struct sockaddr_in *)entry->ifa_addr;
        if (address->sin_addr.s_addr == htonl(INADDR_ANY) ||
            !source_address_advertisable(address->sin_addr) ||
            interface_mac(control_socket, entry->ifa_name, mac))
            continue;
        ifindex = if_nametoindex(entry->ifa_name);
        if (!ifindex)
            continue;
        if (build_packet(packet, &packet_len, fields, mac, address->sin_addr,
                         entry->ifa_name, uptime))
            continue;
        if (!send_packet_on_interface(sender, packet, packet_len, ifindex,
                                      address->sin_addr))
            sent++;
    }
    freeifaddrs(interfaces);
    close(control_socket);
    return sent;
}

static int write_status(const char *path, const char *state, unsigned packets)
{
    struct stat directory_stat, final_stat;
    char directory[PATH_MAX], target[PATH_MAX], temporary[PATH_MAX];
    char *slash;
    int fd, length;
    time_t now = time(NULL);

    if (!path)
        return 0;
    if (strlen(path) >= sizeof(target)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(target, path);
    strcpy(directory, path);
    slash = strrchr(directory, '/');
    if (!slash || slash == directory || !component_name_valid(slash + 1)) {
        errno = EINVAL;
        return -1;
    }
    *slash = '\0';
    if (lstat(directory, &directory_stat) || !S_ISDIR(directory_stat.st_mode) ||
        directory_stat.st_uid != geteuid() ||
        (directory_stat.st_mode & 0777) != 0700) {
        errno = EPERM;
        return -1;
    }
    length = snprintf(temporary, sizeof(temporary), "%s/.neighbor-status.XXXXXX",
                      directory);
    if (length < 0 || (size_t)length >= sizeof(temporary)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    fd = mkstemp(temporary);
    if (fd < 0)
        return -1;
    if (fchmod(fd, 0600) || dprintf(fd, "state=%s\nlast_epoch=%lld\npackets=%u\n",
                                    state, (long long)now, packets) < 0 ||
        fsync(fd) || close(fd)) {
        int saved = errno;
        close(fd);
        unlink(temporary);
        errno = saved;
        return -1;
    }
    if (rename(temporary, target)) {
        int saved = errno;
        unlink(temporary);
        errno = saved;
        return -1;
    }
    if (lstat(target, &final_stat) || !S_ISREG(final_stat.st_mode) ||
        final_stat.st_uid != geteuid() ||
        (final_stat.st_mode & 0777) != 0600 || final_stat.st_nlink != 1) {
        int saved = errno ? errno : EPERM;
        /* rename already consumed the temporary name; never retain an object
         * that failed the post-publication metadata proof. */
        unlink(target);
        errno = saved;
        return -1;
    }
    return 0;
}

static int parse_mac(const char *text, uint8_t mac[6])
{
    unsigned value[6];
    char tail;

    if (sscanf(text, "%2x:%2x:%2x:%2x:%2x:%2x%c", &value[0], &value[1],
               &value[2], &value[3], &value[4], &value[5], &tail) != 6)
        return -1;
    for (size_t i = 0; i < 6; i++)
        mac[i] = (uint8_t)value[i];
    return 0;
}

static int encode_hex(const char *fields_path, const char *mac_text,
                      const char *ip_text, const char *interface_name,
                      const char *uptime_text)
{
    struct neighbor_fields fields;
    struct in_addr ipv4;
    uint8_t packet[PACKET_CAPACITY], mac[6];
    size_t packet_len;
    char *end = NULL;
    unsigned long uptime;

    if (read_fields(fields_path, &fields) || parse_mac(mac_text, mac) ||
        inet_pton(AF_INET, ip_text, &ipv4) != 1 ||
        !source_address_advertisable(ipv4) ||
        !interface_is_lan_bridge(interface_name))
        return 1;
    errno = 0;
    uptime = strtoul(uptime_text, &end, 10);
    if (errno || !end || *end || uptime > UINT32_MAX)
        return 1;
    if (build_packet(packet, &packet_len, &fields, mac, ipv4, interface_name,
                     (uint32_t)uptime))
        return 1;
    for (size_t i = 0; i < packet_len; i++)
        printf("%02x", packet[i]);
    putchar('\n');
    return ferror(stdout) ? 1 : 0;
}

static int drain_selftest(void)
{
    struct sockaddr_in loopback;
    socklen_t loopback_len = sizeof(loopback);
    uint8_t byte = 0xa5;
    unsigned first = 0, second = 0, final = 0;
    int receiver = -1, transmitter = -1;
    int result = 1;

    receiver = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    transmitter = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (receiver < 0 || transmitter < 0)
        goto out;
    memset(&loopback, 0, sizeof(loopback));
    loopback.sin_family = AF_INET;
    loopback.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    loopback.sin_port = 0;
    if (bind(receiver, (struct sockaddr *)&loopback, sizeof(loopback)) ||
        getsockname(receiver, (struct sockaddr *)&loopback, &loopback_len))
        goto out;
    for (unsigned index = 0; index < MNDP_RECEIVE_DRAIN_LIMIT + 16; index++) {
        if (sendto(transmitter, &byte, sizeof(byte), MSG_NOSIGNAL,
                   (struct sockaddr *)&loopback, sizeof(loopback)) !=
            (ssize_t)sizeof(byte))
            goto out;
    }
    if (drain_received_datagrams(receiver, &first) ||
        drain_received_datagrams(receiver, &second) ||
        drain_received_datagrams(receiver, &final))
        goto out;
    if (first != MNDP_RECEIVE_DRAIN_LIMIT || second != 16 || final != 0)
        goto out;
    puts("mndp_drain_selftest=pass");
    result = ferror(stdout) ? 1 : 0;
out:
    if (receiver >= 0)
        close(receiver);
    if (transmitter >= 0)
        close(transmitter);
    return result;
}

static int inject_live_probe(uint16_t destination_port)
{
    struct sockaddr_in loopback;
    uint8_t byte = 0xa5;
    int transmitter = -1;
    int result = 1;

    transmitter = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (transmitter < 0)
        goto out;
    memset(&loopback, 0, sizeof(loopback));
    loopback.sin_family = AF_INET;
    loopback.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    loopback.sin_port = htons(destination_port);
    for (unsigned index = 0; index < MNDP_RECEIVE_DRAIN_LIMIT + 16; index++) {
        if (sendto(transmitter, &byte, sizeof(byte), MSG_NOSIGNAL,
                   (struct sockaddr *)&loopback, sizeof(loopback)) !=
            (ssize_t)sizeof(byte))
            goto out;
    }
    printf("mndp_live_queue_probe=sent:%u\n", MNDP_RECEIVE_DRAIN_LIMIT + 16);
    result = ferror(stdout) ? 1 : 0;
out:
    if (transmitter >= 0)
        close(transmitter);
    return result;
}

static void usage(const char *program)
{
    fprintf(stderr,
             "usage: %s [-d|--daemon] [--status PATH] FIELDS\n"
             "       %s --encode-hex MAC IPv4 IFACE UPTIME FIELDS\n"
             "       %s --drain-selftest\n"
             "       %s --inject-live-probe [PORT]\n"
             "build: %s\n",
             program, program, program, program, build_provenance);
}

int main(int argc, char **argv)
{
    const char *fields_path = NULL, *status_path = NULL;
    bool daemon_mode = false;
    int sender = -1, index = 1;

    if (argc > 1 && !strcmp(argv[1], "--encode-hex")) {
        if (argc != 7) {
            usage(argv[0]);
            return 2;
        }
        return encode_hex(argv[6], argv[2], argv[3], argv[4], argv[5]);
    }
    if (argc == 2 && !strcmp(argv[1], "--drain-selftest"))
        return drain_selftest();
    if ((argc == 2 || argc == 3) && !strcmp(argv[1], "--inject-live-probe")) {
        unsigned long destination_port = MNDP_PORT;
        char *end = NULL;

        if (argc == 3) {
            errno = 0;
            destination_port = strtoul(argv[2], &end, 10);
            if (errno || !end || *end || destination_port < 1 ||
                destination_port > UINT16_MAX) {
                usage(argv[0]);
                return 2;
            }
        }
        return inject_live_probe((uint16_t)destination_port);
    }
    while (index < argc) {
        if (!strcmp(argv[index], "-d") || !strcmp(argv[index], "--daemon")) {
            daemon_mode = true;
            index++;
        } else if (!strcmp(argv[index], "--status") && index + 1 < argc) {
            status_path = argv[index + 1];
            index += 2;
        } else if (argv[index][0] == '-') {
            usage(argv[0]);
            return 2;
        } else if (!fields_path) {
            fields_path = argv[index++];
        } else {
            usage(argv[0]);
            return 2;
        }
    }
    if (!fields_path) {
        usage(argv[0]);
        return 2;
    }
    signal(SIGTERM, stop_handler);
    signal(SIGINT, stop_handler);
    signal(SIGHUP, stop_handler);

    while (keep_running) {
        struct neighbor_fields fields;
        struct sysinfo system_info;
        bool sender_should_run = false;
        unsigned sent = 0, interval = 30;

        if (read_fields(fields_path, &fields)) {
            if (sender >= 0) {
                close(sender);
                sender = -1;
            }
            write_status(status_path, "error", 0);
            if (!daemon_mode)
                return 1;
        } else {
            interval = fields.interval;
            if (!fields.enabled) {
                if (sender >= 0) {
                    close(sender);
                    sender = -1;
                }
                write_status(status_path, "disabled", 0);
                if (!daemon_mode)
                    return 0;
            } else {
                sender_should_run = true;
                if (drain_or_reopen_sender(&sender) && !sysinfo(&system_info))
                    sent = send_round(sender, &fields,
                                      (uint32_t)system_info.uptime);
                if (!drain_or_reopen_sender(&sender))
                    sent = 0;
                write_status(status_path, sent ? "active" : "error", sent);
                if (!daemon_mode)
                    return sent ? 0 : 1;
            }
        }
        if (!daemon_mode)
            break;
        for (unsigned waited = 0; keep_running && waited < interval; waited++) {
            sleep(1);
            if (sender_should_run)
                drain_or_reopen_sender(&sender);
        }
    }
    if (sender >= 0)
        close(sender);
    return 0;
}
