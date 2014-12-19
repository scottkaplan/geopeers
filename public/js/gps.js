//
// Background GPS (phonegap)
//

var background_gps = {
    handle: null,
    init: function () {
	console.log ("init_background_gps - start");
	background_gps.handle = window.plugins.backgroundGeoLocation;
	background_gps.handle.configure(background_gps.callback, background_gps.callback_error, {
	    url: 'https://'+host()+'/api',
	    params: {
		method:    'send_position',
		device_id: device_id_mgr.get(),
	    },
	    notificationTitle: 'Background tracking', // customize the title of the notification
	    notificationText: 'ENABLED',              // customize the text of the notification
	    // Valid values: [0, 10, 100, 1000] (in meters)
	    // The lower the number, the more power devoted to GeoLocation
	    // resulting in higher accuracy readings.
	    // 1000 results in lowest power drain and least accurate readings.
	    // factory default: 10
	    desiredAccuracy: 100,

	    // When stopped, the minimum distance the device must move beyond
	    // the stationary location for aggressive background-tracking to engage.
	    // the plugin cannot detect the exact moment the device moves out of the stationary-radius.
	    // In normal conditions, it can take as much as 3 city-blocks to 1/2 km
	    // before staionary-region exit is detected.
	    // factory default: 20
	    stationaryRadius: 100,

	    // The minimum distance (in meters) a device must move horizontally
	    // before an update event is generated.
	    // factory default: 30
	    distanceFilter: 100, 
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

