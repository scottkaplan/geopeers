//
// Background GPS (phonegap)
//

var background_gps = {
    handle: null,
    init: function () {
	console.log ("init_background_gps - start");
	background_gps.handle = window.plugins.backgroundGeoLocation;
	background_gps.handle.configure(background_gps.callback, background_gps.callback_error, {
		// Android only
		url: 'http://eng.geopeers.com/api',
		    params: {
		    method:    'send_position',
			device_id: device_id_mgr.get(),
			},
		    notificationTitle: 'Background tracking', // customize the title of the notification
		    notificationText: 'ENABLED',              // customize the text of the notification

		    desiredAccuracy: 10,
		    stationaryRadius: 20,
		    distanceFilter: 30, 
		    activityType: 'AutomotiveNavigation',
		    debug: false	// <-- enable this hear sounds for background-geolocation life-cycle.
		    });

	// Turn ON the background-geolocation system.  The user will be tracked whenever they suspend the app.
	background_gps.handle.start();

	// If you wish to turn OFF background-tracking, call the #stop method.
	// background_gps.handle.stop();
	console.log ("init_background_gps - end");
    },
    callback: function (location) {
	// executed every time a geolocation is recorded in the background.
	console.log('callback:' + location.latitude + ',' + location.longitude);
	console.log (this);
	// You must execute the #finish method here
	// to inform the native plugin that you're finished,
	// and the background-task may be completed.
	// IF YOU DON'T, ios will CRASH YOUR APP for spending too much time in the background.
	background_gps.handle.finish();

	// POST location to server
	var request_parms = { gps_longitude: location.longitude,
			      gps_latitude:  location.latitude,
			      method:        'send_position',
			      device_id:     device_id_mgr.get(),
	};
	ajax_request (request_parms);
    },
    callback_error: function(error) {
	console.log('callback error' + error);
    },
};

