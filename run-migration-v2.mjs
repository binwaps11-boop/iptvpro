import { createConnection } from 'mysql2/promise';

const statements = [
  `CREATE TABLE IF NOT EXISTS \`import_jobs\` (
    \`id\` int AUTO_INCREMENT NOT NULL,
    \`importSourceType\` enum('xtream','m3u_file','m3u_url') NOT NULL,
    \`sourceId\` int,
    \`jobStatus\` enum('scanning','previewing','importing','completed','failed','cancelled') NOT NULL DEFAULT 'scanning',
    \`totalScanned\` int DEFAULT 0,
    \`totalImported\` int DEFAULT 0,
    \`totalSkipped\` int DEFAULT 0,
    \`totalFailed\` int DEFAULT 0,
    \`filterSettings\` text,
    \`errorMessage\` text,
    \`logEntries\` text,
    \`startedBy\` int,
    \`startedAt\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    \`completedAt\` timestamp NULL,
    \`createdAt\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    \`updatedAt\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT \`import_jobs_id\` PRIMARY KEY(\`id\`)
  )`,
  `CREATE TABLE IF NOT EXISTS \`playback_logs\` (
    \`id\` int AUTO_INCREMENT NOT NULL,
    \`channelId\` int,
    \`sessionId\` varchar(100),
    \`subscriptionToken\` varchar(100),
    \`eventType\` enum('play_start','play_stop','buffer_stall','quality_switch','source_fallback','error_network','error_media','error_decode','error_timeout','error_manifest','recovery_success','recovery_failed') NOT NULL,
    \`engine\` varchar(50),
    \`quality\` varchar(50),
    \`bufferHealth\` int,
    \`networkSpeed\` int,
    \`errorDetails\` text,
    \`streamUrl\` text,
    \`userAgent\` text,
    \`ipAddress\` varchar(45),
    \`createdAt\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT \`playback_logs_id\` PRIMARY KEY(\`id\`)
  )`,
  `CREATE TABLE IF NOT EXISTS \`source_health\` (
    \`id\` int AUTO_INCREMENT NOT NULL,
    \`channelId\` int NOT NULL,
    \`streamUrl\` text NOT NULL,
    \`healthStatus\` enum('healthy','degraded','down','timeout') NOT NULL,
    \`httpStatus\` int,
    \`responseTimeMs\` int,
    \`contentType\` varchar(100),
    \`errorMessage\` text,
    \`checkedAt\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT \`source_health_id\` PRIMARY KEY(\`id\`)
  )`,
  `CREATE TABLE IF NOT EXISTS \`stream_variants\` (
    \`id\` int AUTO_INCREMENT NOT NULL,
    \`channelId\` int NOT NULL,
    \`url\` text NOT NULL,
    \`priority\` int NOT NULL DEFAULT 0,
    \`format\` enum('m3u8','ts','mp4','mpd','rtmp','other') DEFAULT 'm3u8',
    \`variantStatus\` enum('online','offline','unknown') DEFAULT 'unknown',
    \`lastCheck\` timestamp NULL,
    \`responseTimeMs\` int,
    \`lastError\` text,
    \`createdAt\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT \`stream_variants_id\` PRIMARY KEY(\`id\`)
  )`,
];

// ALTER TABLE statements - each wrapped in try/catch for idempotency
const alterStatements = [
  "ALTER TABLE `channels` ADD `country` varchar(100)",
  "ALTER TABLE `channels` ADD `language` varchar(100)",
  "ALTER TABLE `channels` ADD `quality` varchar(50)",
  "ALTER TABLE `channels` ADD `channelStatus` enum('online','offline','unknown') DEFAULT 'unknown'",
  "ALTER TABLE `channels` ADD `rawMetadata` text",
  "ALTER TABLE `channels` ADD `contentHash` varchar(64)",
  "ALTER TABLE `stream_sources` ADD `srcHealthStatus` enum('healthy','degraded','down','unknown') DEFAULT 'unknown'",
  "ALTER TABLE `stream_sources` ADD `lastHealthCheck` timestamp NULL",
];

async function run() {
  const conn = await createConnection(process.env.DATABASE_URL);
  console.log('Connected to database');
  
  for (const sql of statements) {
    try {
      await conn.execute(sql);
      console.log('✓ Created table');
    } catch (e) {
      console.log('⚠ Table may already exist:', e.message?.substring(0, 80));
    }
  }
  
  for (const sql of alterStatements) {
    try {
      await conn.execute(sql);
      console.log('✓ ALTER:', sql.substring(0, 60));
    } catch (e) {
      console.log('⚠ Column may already exist:', e.message?.substring(0, 80));
    }
  }
  
  // Add indexes for performance
  const indexes = [
    "CREATE INDEX idx_channels_content_hash ON channels(contentHash)",
    "CREATE INDEX idx_channels_content_type ON channels(contentType)",
    "CREATE INDEX idx_channels_source_id ON channels(sourceId)",
    "CREATE INDEX idx_stream_variants_channel ON stream_variants(channelId)",
    "CREATE INDEX idx_playback_logs_channel ON playback_logs(channelId)",
    "CREATE INDEX idx_playback_logs_created ON playback_logs(createdAt)",
    "CREATE INDEX idx_source_health_channel ON source_health(channelId)",
    "CREATE INDEX idx_import_jobs_status ON import_jobs(jobStatus)",
  ];
  
  for (const sql of indexes) {
    try {
      await conn.execute(sql);
      console.log('✓ Index:', sql.substring(0, 60));
    } catch (e) {
      console.log('⚠ Index may exist:', e.message?.substring(0, 60));
    }
  }
  
  console.log('\n✅ Migration complete!');
  await conn.end();
}

run().catch(e => { console.error('Migration failed:', e); process.exit(1); });
