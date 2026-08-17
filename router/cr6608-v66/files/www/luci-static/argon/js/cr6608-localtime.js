/* Keep mixed Arabic/Latin LuCI time strings in their logical visual order. */
(function () {
	"use strict";

	var MARK_RE = /[\u2066-\u2069]/g;
	var TOKEN_RE = /[\u0621-\u063A\u0641-\u064A\u064B-\u065F\u066E-\u06D3\u06FA-\u06FF]+|[A-Za-z0-9\u0660-\u0669\u06F0-\u06F9:+.\/,\-]+/g;
	var RTL_RE = /[\u0621-\u063A\u0641-\u064A\u066E-\u06D3\u06FA-\u06FF]/;
	var SELECTOR = [
		'body[data-page="admin-system-system"] #localtime',
		'body[data-page="admin-status-overview"] #view > .cbi-section:first-child .table .tr:nth-child(7) > .td:last-child'
	].join(",");

	function plain(value) {
		return String(value == null ? "" : value).replace(MARK_RE, "");
	}

	function isolateTokens(value) {
		return plain(value).replace(TOKEN_RE, function (token) {
			return (RTL_RE.test(token) ? "\u2067" : "\u2066") + token + "\u2069";
		});
	}

	function apply(element) {
		var isField = "value" in element;
		var current = isField ? element.value : element.textContent;
		var source = plain(current);
		var isolated = isolateTokens(source);

		if (element.getAttribute("dir") !== "ltr")
			element.setAttribute("dir", "ltr");
		if (element.getAttribute("aria-label") !== source)
			element.setAttribute("aria-label", source);
		if (!element.classList.contains("cr6608-localtime-bidi"))
			element.classList.add("cr6608-localtime-bidi");

		if (current !== isolated) {
			if (isField)
				element.value = isolated;
			else
				element.textContent = isolated;
		}
	}

	function sync() {
		document.querySelectorAll(SELECTOR).forEach(apply);
	}

	function start() {
		var page = document.body && document.body.getAttribute("data-page");
		if (page !== "admin-system-system" && page !== "admin-status-overview")
			return;

		sync();
		new MutationObserver(sync).observe(document.body, {
			childList: true,
			characterData: true,
			subtree: true
		});
		window.setInterval(sync, 500);
	}

	if (document.readyState === "loading")
		document.addEventListener("DOMContentLoaded", start, { once: true });
	else
		start();
})();
