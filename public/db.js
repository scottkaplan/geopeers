var db = {
    // this is only supported in phonegap, not web app
    handle: null,
    init: function () {
	db.handle = window.sqlitePlugin.openDatabase({name: "geopeers.db"});
	db.handle.transaction(function(tx) {
		tx.executeSql('DROP TABLE IF EXISTS globals');
		tx.executeSql('CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)');
	    });
    },
    get_global: function (key, callback) {
	db.handle.transaction(function (tx) {
		tx.executeSql('SELECT value FROM globals WHERE "key" = ?', [key], function(tx, response) {
			callback (response);
		    },
		    db.error_callback);
	    });
    },
    set_global: function (key, value) {
	db.handle.transaction(function (tx) {
		tx.executeSql('REPLACE INTO globals ("key", value) VALUES (?,?)', [key, value], null , db.error_callback);
	    });
    },
    error_callback: function (err) {
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
