var db = {
    // this is only supported in phonegap, not web app
    handle: null,
    init_OK: function () {
	db.handle = window.sqlitePlugin.openDatabase({name: "my.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('DROP TABLE IF EXISTS test_table');
		tx.executeSql('CREATE TABLE IF NOT EXISTS test_table (id integer primary key, data text, data_num integer)');

		tx.executeSql("INSERT INTO test_table (data, data_num) VALUES (?,?)", ["test", 100], function(tx, res) {
			console.log("insertId: " + res.insertId + " -- probably 1");
			console.log("rowsAffected: " + res.rowsAffected + " -- should be 1");

			tx.executeSql("select count(id) as cnt from test_table;", [], function(tx, res) {
				console.log("res.rows.length: " + res.rows.length + " -- should be 1");
				console.log("res.rows.item(0).cnt: " + res.rows.item(0).cnt + " -- should be 1");
			    });

		    }, function(e) {
			console.log("ERROR: " + e.message);
		    });
	    });
    },
    init_BAD: function () {
	db.handle = window.sqlitePlugin.openDatabase({name: "my.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)');
		tx.executeSql('INSERT INTO globals ("key", value) VALUES (?,?)', ['foo', '52'], function(tx, res) {
			console.log("insertId: " + res.insertId);
			console.log("rowsAffected: " + res.rowsAffected);

			tx.executeSql('SELECT value FROM globals WHERE "key" = ?', [key], function(tx, res) {
				console.log("res.rows.length: " + res.rows.length);
				console.log("res.rows.item(0).value: " + res.rows.item(0).value);
			    });

		    }, function(e) {
			console.log("ERROR: " + e.message);
		    });
	    });
    },
    init_OK_2: function () {
	db.handle = window.sqlitePlugin.openDatabase({name: "geopeers.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)');
		tx.executeSql('REPLACE INTO globals ("key", value) VALUES (?,?)', ['foo', '52'], function(tx, res) {
			console.log("insertId: " + res.insertId);
			console.log("rowsAffected: " + res.rowsAffected);
			tx.executeSql('SELECT COUNT(*) AS cnt FROM globals', [], function(tx, res) {
				console.log("res.rows.length: " + res.rows.length);
				console.log("res.rows.item(0).cnt: " + res.rows.item(0).cnt);
			    },
			    db.error_callback);
		    },
		    db.error_callback);
	    });
    },
    init_OK_3: function () {
	db.handle = window.sqlitePlugin.openDatabase({name: "geopeers.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)');
		tx.executeSql('REPLACE INTO globals ("key", value) VALUES (?,?)', ['foo', '52'], function(tx, res) {
			console.log("insertId: " + res.insertId);
			console.log("rowsAffected: " + res.rowsAffected);
			tx.executeSql('SELECT value FROM globals WHERE "key" = ?', ['foo'], function(tx, res) {
				console.log("res.rows.length: " + res.rows.length);
				console.log("res.rows.item(0).value: " + res.rows.item(0).value);
			    },
			    db.error_callback);
		    },
		    db.error_callback);
	    });
    },
    init: function () {
	db.handle = window.sqlitePlugin.openDatabase({name: "geopeers.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)');
	    });
    },
    get_global: function (key, callback) {
	console.log ("in get_global");
	db.handle.transaction(function (tx) {
		tx.executeSql('SELECT value FROM globals WHERE "key" = ?', [key], function(tx, response) {
			callback (response);
		    },
		    db.error_callback);
	    });
    },
    set_global: function (key, value) {
	console.log ("in set_global");
	db.handle.transaction(function (tx) {
		tx.executeSql('REPLACE INTO globals ("key", value) VALUES (?,?)', [key, value], function(tx, res) {
			console.log("insertId: " + res.insertId);
			console.log("rowsAffected: " + res.rowsAffected);
		    },
		    db.error_callback);
	    });
    },
    error_callback: function (err) {
	console.log (err.message);
    },
};

function display_db_row (response) {
    console.log("value: " + response.rows.item(0).value);
    return;
}

document.addEventListener("deviceready", onDeviceReady, false);

// Cordova is ready
function onDeviceReady() {
    alert ("Start");

    if (0) {
	boneyard ();
    }

    if (1) {
	db.init ();
	setTimeout(function(){
		db.get_global ('foo', display_db_row);
	    }, 1000);

	// db.set_global ('foo', '42');
	// db.get_global ('foo', function (val) {console.log("got "+val)});
    }
}

function boneyard() {
    db.handle.transaction(function(tx) {
	    tx.executeSql('DROP TABLE IF EXISTS test_table');
	    tx.executeSql('CREATE TABLE IF NOT EXISTS test_table (id integer primary key, data text, data_num integer)');

	    tx.executeSql("INSERT INTO test_table (data, data_num) VALUES (?,?)", ["test", 100], function(tx, res) {
		    console.log("insertId: " + res.insertId + " -- probably 1");
		    console.log("rowsAffected: " + res.rowsAffected + " -- should be 1");

		    tx.executeSql("select count(id) as cnt from test_table;", [], function(tx, res) {
			    console.log("res.rows.length: " + res.rows.length + " -- should be 1");
			    console.log("res.rows.item(0).cnt: " + res.rows.item(0).cnt + " -- should be 1");
			});

		}, function(e) {
		    console.log("ERROR: " + e.message);
		});
	});
}
