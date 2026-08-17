return {
	action_logout: function() {
		if (ctx.authsession)
			ubus.call('session', 'destroy', { ubus_rpc_session: ctx.authsession });

		http.prepare_content('text/html; charset=UTF-8');
		http.header('Cache-Control', 'no-store');
		http.header('X-Frame-Options', 'DENY');
		http.header('Content-Security-Policy', "default-src 'none'; script-src 'sha256-6IvnprXjjOfzbDlCSnA/4vJOIPLjEaRMCuo81obFgXs='; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
		http.write(`<!doctype html>
<html><head><meta charset="utf-8"><title>Logout</title></head>
<body>
<form id="cr6608-logout" method="post" action="/cgi-bin/dashlogout">
<input type="hidden" name="redirect" value="1">
<button type="submit">Continue</button>
</form>
<script>document.getElementById('cr6608-logout').submit();</script>
</body></html>`);
	}
};
