var db = {
    handle: null,
    init: function (callback) {
	if (! db.handle) {
	    db.handle = window.sqlitePlugin.openDatabase({name: "geopeers.db"});
	}
	db.handle.transaction(function(tx) {
		sql = 'CREATE TABLE IF NOT EXISTS globals ("key" text unique, value text)';
		console.log (sql);
		tx.executeSql(sql, [],
			      function (tx, response) {
				  // nothing to return to callback
				  callback();
			      },
			      db.error_callback);
	    });
    },
    reset: function (callback) {
	db.handle.transaction(
			      function(tx) {
				  sql = 'DROP TABLE IF EXISTS globals';
				  console.log (sql);
				  tx.executeSql(sql, [], function (tx, response) {db.init(callback)});
			      },
			      function (err) {db.error_callback(err)}
			      );
    },
    get_global: function (key, callback) {
	db.handle.transaction(
			      function (tx) {
				  sql = 'SELECT value FROM globals WHERE "key" = ?';
				  console.log (sql);
				  tx.executeSql(sql, [key],
						function (tx, response) {
						    callback(db.get_val_from_response(response));
						});
			      },
			      function (err) {db.error_callback(err)}
			      );
    },
    set_global: function (key, value, callback) {
	db.handle.transaction(
			      function (tx) {
				  sql = 'REPLACE INTO globals ("key", value) VALUES (?,?)';
				  console.log (sql);
				  tx.executeSql(sql, [key, value],
						function (tx, response) {
						    if (callback) {
							// nothing to return to callback
							callback();
						    }
						});
			      },
			      function (err) {db.error_callback(err)}
			      );
    },
    error_callback: function (err) {
	console.log (JSON.stringify(err));
	console.log (err.message);
    },
    get_val_from_response: function (response) {
	if (response &&
	    response.rows &&
	    response.rows.item(0)) {
	    return (response.rows.item(0).value);
	} else {
	    return (null);
	}
    },
};

function log_msg (msg) {
    $('#results').append(msg + '<br>');
    return;
}

function step_4 (val) {
    log_msg (val);
}

function step_3 () {
    log_msg ("getting foo again");
    db.get_global ('foo', step_4);
}

function step_2 (val) {
    log_msg (val);
    if (val) {
	val = parseInt(val) + 10;
    } else {
	val = 10;
    }
    log_msg ("setting foo = "+val);
    db.set_global ('foo', val, step_3);
}

function step_1 () {
    log_msg ("getting foo");
    db.get_global ('foo', step_2);
}

function unit_test () {
    log_msg ("starting");
    db.init (step_1);
}

function reset_test () {
    db.init (function () {db.reset(step_1)});
}

document.addEventListener("deviceready", unit_test, false);
