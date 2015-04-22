#!/usr/bin/env node


var zfs = require('zfs').zfs,
    s = require('underscore.string'),
    c = require('chalk'),

    arg = process.argv[2] || '';


var FilterFunction = function(snap) {
    if (arg.length == 0) return true;
    var s = snap.name.split('@')[0];
    console.log(c.red('comparing ', s, 'to', arg));
    return false;
};

zfs.list_snapshots('tank/Rick@R',function(err, fields, list) {
    if (err) throw err;
    list = list.map(function(l) {
        return {
            name: l[0],
            used: l[1],
            avail: l[2],
            refer: l[3],
            type: l[4],
            mountpoint: l[5],
        };
    }).filter(FilterFunction);
    console.log(JSON.stringify(list));
});
