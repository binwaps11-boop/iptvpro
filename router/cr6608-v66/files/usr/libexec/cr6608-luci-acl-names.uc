#!/usr/bin/ucode

import { glob, readfile } from 'fs';

let seen = {};

for (let path in glob('/usr/share/rpcd/acl.d/*.json')) {
	let source = readfile(path);
	let document;

	if (type(source) != 'string')
		continue;

	try {
		document = json(source);
	}
	catch (e) {
		continue;
	}

	if (type(document) != 'object')
		continue;

	for (let name in keys(document))
		seen[name] = true;
}

for (let name in keys(seen))
	print(name, '\n');
