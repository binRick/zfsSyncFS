#!/usr/bin/env node

var pj = require('prettyjson'),
    _ = require('underscore'),
    async = require('async'),
    c = require('chalk'),
    zfs = require(__dirname + '/node-zfs').zfs,
    s = require('underscore.string'),
    fs = process.argv[2] || 't/Rick',
    remote = process.argv[3] || 'beo',
    local = require('os').hostname().split('.')[0],
    Client = require('ssh2').Client,
    conn = new Client();


var remotePath = 'tank/Snapshots/' + local;


var SnapFilter = function(l) {
        return l.name.split('@')[0] == fs;
    },
    RemoteSnapFilter = function(l) {
        var Match = 'tank/Snapshots/' + local + '/' + fs;
        var M = l.name.split('@')[0];
        if (M == Match)
            console.log(c.red('Match!'), c.green(Match), c.magenta(M));
        return M == Match;
    };

var getRemoteSnapshots = function(cb) {
    conn.on('ready', function() {
        console.log(c.green('SSH Connected to ', remote));
        conn.exec('node /root/bin/zfsListSnapshots.js', function(err, stream) {
            if (err) throw err;
            var o = [];
            stream.on('close', function(code, signal) {
                conn.end();
                var J = JSON.parse(o.join(''));
                var RemoteSnaps = J.filter(RemoteSnapFilter);
                cb(null, {
                    Type: 'Remote',
                    Data: RemoteSnaps
                });
            }).on('data', function(data) {
                o.push(data);
            }).stderr.on('data', function(data) {
                return cb(data, null);
            });
        });
    }).connect({
        host: remote,
        port: 22,
        username: 'root',
        privateKey: require('fs').readFileSync('/root/.ssh/shared')
    });
};

var getLocalSnapshots = function(cb) {
    /*
     *
     *
     *      written: '1189376',
     *           logicalused: '2784256',
     *                logicalreferenced: '2724864',
     *
     *
     *      usedbysnapshots: '143360',
     *           usedbydataset: '3096576',
     *                usedbychildren: '0',
     *
     *    { type: 'filesystem',
     *         creation: '1427498900',
     *              used: '150056960',
     *                   available: '52122885120',
     *                        referenced: '149904896',
     *
     *      recordsize: '131072',
     *           mountpoint: '/t/Rick',
     *
     *      mounted: 'yes',
     *           quota: '0',
     *
     * */
    zfs.get(fs, ['all'], [], function(e, i) {
        if (e) throw e;
 //       console.log(i);
    });
    zfs.list_snapshots(function(err, fields, list) {
        if (err) throw err;
        list = list.map(function(l, index, arr) {
            var P = arr[index - 1] || [];
            P = P[0] || '';
            P = P.split('@')[1] || '';

            return {
                name: l[0],
                used: l[1],
                avail: l[2],
                refer: l[3],
                type: l[4],
                mountpoint: l[5],
                prevSnap: P,
            };
        }).filter(SnapFilter);
        cb(null, {
            Type: 'Local',
            Data: list
        });
    });
};

async.parallel([getLocalSnapshots, getRemoteSnapshots], function(err, Snapshots) {
    var Snaps = {};
    Snaps.Remote = Snapshots.filter(function(s) {
        return s.Type == 'Remote';
    }).map(function(s) {
        return s.Data;
    });
    Snaps.Local = Snapshots.filter(function(s) {
        return s.Type == 'Local';
    }).map(function(s) {
        return s.Data;
    });
    Snaps.Local = _.flatten(Snaps.Local);
    Snaps.Remote = _.flatten(Snaps.Remote);
    Snaps.RemoteNames = Snaps.Remote.map(function(s) {
        return s.name.split('@')[1];
    });
    Snaps.LocalNames = Snaps.Local.map(function(s) {
        return s.name.split('@')[1];
    });
    Snaps.toSyncNames = Snaps.LocalNames.filter(function(n) {
        return !_.contains(Snaps.RemoteNames, n);
    });
    Snaps.toSync = Snaps.Local.filter(function(s) {
        return _.contains(Snaps.toSyncNames, s.name.split('@')[1]);
    });
    Snaps.SyncCommands = Snaps.toSync.map(function(s) {
if(s.prevSnap.length>0)
s.prevSnap = ' -i ' + s.prevSnap; 
        return 'zfs send ' + s.prevSnap + ' ' + s.name + ' | pv | ssh ' + remote + ' zfs recv -vF ' + remotePath + '/' + fs;
    });
    console.log(Snaps);
    if (err) throw err;
});
//};
