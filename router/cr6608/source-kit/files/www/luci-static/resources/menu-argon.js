'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	__init__: function() {
		this.loadMenu(0);
	},

	loadMenu: function(attempt) {
		var self = this;
		this.loadMenuWithTimeout(5000).then(function(tree) {
			if (attempt > 0) {
				var mainmenu = document.querySelector('#mainmenu');
				var tabmenu = document.querySelector('#tabmenu');
				if (mainmenu) mainmenu.innerHTML = '';
				if (tabmenu) tabmenu.innerHTML = '';
			}
			self.render(tree);
		}).catch(function(error) {
			if (attempt < 1) {
				window.setTimeout(function() { self.loadMenu(attempt + 1); }, 500);
				return;
			}
			self.renderLoadFailure(error);
		});
	},

	loadMenuWithTimeout: function(timeoutMs) {
		return new Promise(function(resolve, reject) {
			var settled = false;
			var timer = window.setTimeout(function() {
				if (settled) return;
				settled = true;
				reject(new Error('menu-load-timeout'));
			}, timeoutMs);
			function finish(callback, value) {
				if (settled) return;
				settled = true;
				window.clearTimeout(timer);
				callback(value);
			}
			try {
				ui.menu.load().then(function(tree) { finish(resolve, tree); }, function(error) { finish(reject, error); });
			} catch (error) {
				finish(reject, error);
			}
		});
	},

	renderLoadFailure: function() {
		this.bindSidebarControls();
		var container = document.querySelector('#mainmenu');
		var tabmenu = document.querySelector('#tabmenu');
		if (!container) return;
		if (tabmenu) tabmenu.innerHTML = '';
		container.style.display = '';
		container.innerHTML = '';
		container.appendChild(E('div', { 'class': 'alert-message warning', 'role': 'alert' }, [
			E('p', {}, _('Navigation could not be loaded. Your session or the menu service may need a refresh.')),
			E('button', { 'class': 'btn cbi-button-action', 'click': function() { window.location.reload(); } }, _('Reload menu'))
		]));
	},

	render: function(tree) {
		var node = tree, url = '', children = ui.menu.getChildren(tree);
		for (var i = 0; i < children.length; i++) {
			var isActive = L.env.requestpath.length ? children[i].name == L.env.requestpath[0] : i == 0;
			if (isActive) this.renderMainMenu(children[i], children[i].name);
		}
		if (L.env.dispatchpath.length >= 3) {
			for (var j = 0; j < 3 && node; j++) {
				node = node.children[L.env.dispatchpath[j]];
				url = url + (url ? '/' : '') + L.env.dispatchpath[j];
			}
			if (node) this.renderTabMenu(node, url);
		}
		this.bindSidebarControls();
	},

	bindSidebarControls: function() {
		var self = this;
		var showSide = document.querySelector('a.showSide');
		var darkMask = document.querySelector('.darkMask');
		var bindOnce = function(element) {
			if (!element || element.getAttribute('data-cr6608-sidebar-bound') == '1') return;
			element.addEventListener('click', ui.createHandlerFn(self, 'handleSidebarToggle'));
			element.setAttribute('data-cr6608-sidebar-bound', '1');
		};
		if (showSide) {
			showSide.setAttribute('aria-controls', 'mainmenu');
			showSide.setAttribute('aria-expanded', showSide.classList.contains('active') ? 'true' : 'false');
		}
		bindOnce(showSide);
		bindOnce(darkMask);
	},

	handleMenuExpand: function(ev) {
		var a = ev.currentTarget || ev.target, slide = a.parentNode, slideMenu = a.nextElementSibling;
		var collapse = false;
		document.querySelectorAll('.main .main-left .nav > li > ul.active').forEach(function(ul) {
			$(ul).stop(true).slideUp('fast', function() {
				ul.classList.remove('active');
				ul.previousElementSibling.classList.remove('active');
			});
			if (!collapse && ul === slideMenu) collapse = true;
		});
		if (slideMenu && !collapse) {
			$(slide).find('.slide-menu').slideDown('fast', function() {
				slideMenu.classList.add('active');
				a.classList.add('active');
			});
			a.blur();
		}
		ev.preventDefault();
		ev.stopPropagation();
	},

	renderMainMenu: function(tree, url, level) {
		var l = (level || 0) + 1;
		var ul = E('ul', { 'class': level ? 'slide-menu' : 'nav' });
		var children = ui.menu.getChildren(tree);
		if (children.length == 0 || l > 2) return E([]);
		for (var i = 0; i < children.length; i++) {
			var isActive = L.env.dispatchpath[l] == children[i].name && L.env.dispatchpath[l - 1] == tree.name;
			var submenu = this.renderMainMenu(children[i], url + '/' + children[i].name, l);
			var hasChildren = submenu.children.length;
			var expandHandler = l == 1 && hasChildren ? ui.createHandlerFn(this, 'handleMenuExpand') : null;
			var slideClass = hasChildren ? 'slide' : '';
			var menuClass = hasChildren ? 'menu' : 'food';
			if (isActive) {
				ul.classList.add('active');
				slideClass += ' active';
				menuClass += ' active';
			}
			ul.appendChild(E('li', { 'class': slideClass }, [
				E('a', {
					'href': L.url(url, children[i].name),
					'click': expandHandler,
					'class': menuClass,
					'data-title': children[i].title.replace(' ', '_')
				}, [ _(children[i].title) ]),
				submenu
			]));
		}
		if (l == 1) {
			var mainmenu = document.querySelector('#mainmenu');
			if (mainmenu) {
				mainmenu.appendChild(ul);
				mainmenu.style.display = '';
			}
		}
		return ul;
	},

	renderTabMenu: function(tree, url, level) {
		var container = document.querySelector('#tabmenu');
		var l = (level || 0) + 1;
		var ul = E('ul', { 'class': 'tabs' });
		var children = ui.menu.getChildren(tree), activeNode = null;
		if (children.length == 0 || !container) return E([]);
		for (var i = 0; i < children.length; i++) {
			var isActive = L.env.dispatchpath[l + 2] == children[i].name;
			var activeClass = isActive ? ' active' : '';
			var className = 'tabmenu-item-%s %s'.format(children[i].name, activeClass);
			ul.appendChild(E('li', { 'class': className }, [
				E('a', { 'href': L.url(url, children[i].name) }, [ _(children[i].title) ])
			]));
			if (isActive) activeNode = children[i];
		}
		container.appendChild(ul);
		container.style.display = '';
		if (activeNode) container.appendChild(this.renderTabMenu(activeNode, url + '/' + activeNode.name, l));
		return ul;
	},

	handleSidebarToggle: function(ev) {
		var showSide = document.querySelector('a.showSide');
		var sidebar = document.querySelector('#mainmenu');
		var darkMask = document.querySelector('.darkMask');
		var scrollbar = document.querySelector('.main-right');
		if (ev) {
			ev.preventDefault();
			ev.stopPropagation();
		}
		if (!showSide || !sidebar || !darkMask || !scrollbar) return;
		var open = !showSide.classList.contains('active');
		showSide.classList.toggle('active', open);
		sidebar.classList.toggle('active', open);
		scrollbar.classList.toggle('active', open);
		darkMask.classList.toggle('active', open);
		showSide.setAttribute('aria-expanded', open ? 'true' : 'false');
	}
});
