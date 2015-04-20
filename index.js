#!/usr/bin/env node

//# export FS="aPool/9894631" && export REMOTE="crater" && alias i="./index.js" && alias p="prettyjson" && alias o="i | p"
var pb = require('pretty-bytes'),
    ta = require('time-ago'),
    ago = require('ago'),
    POOL = 'tank',
    moment = require('moment');

var pj = require('prettyjson'),
    _ = require('underscore'),
    async = require('async'),
    c = require('chalk'),
    zfs = require(__dirname + '/node-zfs').zfs,
    zpool = require(__dirname + '/node-zfs').zpool,
    s = require('underscore.string'),
    fs = process.env.FS || process.argv[2] || 't/Rick',
    remote = process.env.REMOTE || process.argv[3] || 'beo',
    local = require('os').hostname().split('.')[0],
    Client = require('ssh2').Client,
    conn = new Client();

var normalizePoolVals = function(a, b) {
    var i, index, V = 0,
        c = {};
    for (V in b)
        for (i in a)
            c[a[i]] = b[V][i];
    return c;
};

var allZfsFields = ['all'],
    customFields = [{
        field: '_backup_interval',
        default: 84600
    }],
    zfsFields = ['used', 'usedbysnapshots', 'atime', 'compressratio', 'logicalreferenced', 'mountpoint', 'mounted', 'creation', 'refcompressratio', 'available', 'referenced', 'dedup', 'logicalused', 'type', 'usedbydataset', 'creation', 'quota'];
var zfsFieldsPlusCustom = zfsFields.concat(customFields.map(function(f) {
        return 'custom:' + f.field;
    })),
    remotePath = 'tank/Snapshots/' + local;

var SnapshotsParser = function(fs, cb) {
        return zfs.get(fs, zfsFields, [], cb);
    },
    SnapFilter = function(l) {
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
    zfs.list_snapshots(function(err, fields, list) {
        if (err) throw err;
        var Snapshots = list.map(function(l, index, arr) {
            var P = arr[index - 1] || [];
            P = P[0] || '';
            P = P.split('@')[1] || '';
            if (index == 0) P = '';
            return {
                name: l[0],
                used: l[1],
                avail: l[2],
                refer: l[3],
                type: l[4],
                mountpoint: l[5],
                SnapshotListIndex: index,
            };
        }).filter(SnapFilter);
        var e = null;
        cb(e, {
            Type: 'Local',
            Data: Snapshots
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
    Snaps.SyncCommands = Snaps.toSync.map(function(s, i, ar) {
        s.pvOptions = s.pvOptions || '';
        if (s.LocalIndex == 0)
            p.prevSnap = '';
        return 'zfs send ' + s.prevSnap + ' ' + s.name + ' | pv ' + s.pvOptions + ' | ssh ' + remote + ' zfs recv -vF ' + remotePath + '/' + fs;
    });
    Snaps.fsInfo = {};
    zpool.list(POOL, ['all'], function(e, poolFields, poolValues) {
        if (e) throw e;
        Snaps.poolInfo = normalizePoolVals(poolFields, poolValues);
        SnapshotsParser(fs, function(e, lInfo) {
            if (e) throw e;
            Snaps.fsInfo.Local = lInfo[fs];
            Snaps.fsSummary = {
                Bytes: Snaps.fsInfo.Local.used,
                Size: pb(parseInt(Snaps.fsInfo.Local.used)),
                Snapshots: Snaps.Local.length,
                CreationTs: parseInt(Snaps.fsInfo.Local.creation),
                Creation: moment.unix(Snaps.fsInfo.Local.creation),
                CTID: '12345',
            };
            console.log(JSON.stringify(Snaps))
        });
    });
});