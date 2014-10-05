var db = {
    // this is only supported in phonegap, not web app
    handle: null,
    init: function () {
	if (db.handle) {
	    return;
	}
	db.handle = window.sqlitePlugin.openDatabase({name: "geopeers.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)');
	    });
    },
    reset: function () {
	db.handle.transaction(function(tx) {
		tx.executeSql('DROP TABLE IF EXISTS globals');
	    }, db.init())
    },
    get_global: function (key, callback) {
	db.handle.transaction(function (tx) {
		tx.executeSql('SELECT value FROM globals WHERE "key" = ?', [key], function(tx, response) {
			callback (tx, response);
		    },
		    db.error_callback);
	    });
    },
    set_global: function (key, value) {
	db.handle.transaction(function (tx) {
		tx.executeSql('REPLACE INTO globals ("key", value) VALUES (?,?)', [key, value], set_callback , db.error_callback);
	    });
    },
    set_callback: function  (tx, results) {
	console.log (tx);
	console.log (results);
	console.log (results.rows);
    },
    error_callback: function (err) {
	console.log (err);
	console.log (err.message);
    },
};

function display_db_row (response) {
    if (response && response.rows && response.rows.item(0)) {
	console.log (response.rows.item(0).value);
    } else {
	console.log (null);
    }
    return;
}

// document.addEventListener("deviceready", unit_test, false);

function unit_test() {
    alert ("Start");

    db.init ();
    db.get_global ('foo', display_db_row);
    db.set_global ('foo', '32');
    db.get_global ('foo', display_db_row);
}
