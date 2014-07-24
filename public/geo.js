var REGISTER_STATE;
var MAP;

function is_def (v) {
    var ret = ((v != undefined) && (v != null))
    return (ret);
}

function display_in_div (msg, div_id, style) {
    div_id = (typeof div_id === "undefined") ? "geo_error" : div_id;
    if (typeof msg === 'object') {
	msg = JSON.stringify (msg);
    }
    $('#'+div_id).html(msg);
    if (is_def (style)) {
	$('#'+div_id).css(style);
    }
}

function display_error (msg) {
    display_in_div (msg, 'geo_error');
    return;
}

function geo_ajax_success_callback (data, textStatus, jqXHR) {
    if (data.message) {
	display_in_div (data.message, 'geo_info');
    }
    if (data.js) {
	eval (data.js);
    }
    return;
}

function geo_ajax_fail_callback (data, textStatus, jqXHR) {
    var error_html;
    if (typeof (data.error) === 'string') {
	error_html = data.error_html ? data.error_html : data.error;
    } else if (data.responseJSON) {
	error_html = data.responseJSON.error_html ? data.responseJSON.error_html : data.responseJSON.error;
    }
    display_in_div (error_html, 'geo_error');
    $('#registration_form_spinner').hide();
    $('#share_location_form_spinner').hide();
    return;
}

function ajax_request (request_parms, success_callback) {
    var url = "http://www.geopeers.com/api";
    $.ajax({type:  "POST",
	    async: true,
	    url:   url,
	    data:  request_parms,
	  })
	.done(success_callback)
	.fail(geo_ajax_fail_callback);
    return;
}

function send_position_request (position) {
    var device_id = get_cookie('device_id');
    if (! is_def (device_id))
	return
    var request_parms = { gps_longitude: position.coords.longitude,
			  gps_latitude:  position.coords.latitude,
			  method:        'send_position',
			  device_id:     device_id,
    };
    ajax_request (request_parms, geo_ajax_success_callback);
    return;
}

function get_cookie(cname) {
    var name = cname + "=";
    var ca = document.cookie.split(';');
    for(var i=0; i<ca.length; i++) {
        var c = ca[i];
        while (c.charAt(0)==' ') c = c.substring(1);
        if (c.indexOf(name) != -1) return c.substring(name.length,c.length);
    }
    return;
}

function get_positions () {
    var device_id = get_cookie('device_id');
    if (! is_def (device_id))
	return
    var request_parms = { method: 'get_positions',
			  device_id: device_id};
    ajax_request (request_parms, update_markers);
    return;
}

$(document).ready(function(e,data){
	// Try W3C Geolocation (Preferred)
	if(navigator.geolocation) {
	    navigator.geolocation.getCurrentPosition(function(position) {init_map(position)},
						     function() {init_map()});
	} else {
	    // Browser doesn't support Geolocation
	    init_map();
	}
	get_positions();
    });

function init_map (position) {
    var initial_location;
    var zoom_level = 13;
    if (is_def (position)) {
	initial_location = new google.maps.LatLng(position.coords.latitude,
						  position.coords.longitude);
	send_position_request (position);
    }
    MAP = new google.maps.Map(document.getElementById('map_canvas'), {
	    zoom: zoom_level,
	    center: initial_location,
	    mapTypeId: google.maps.MapTypeId.ROADMAP,
	});
    if (is_def (position)) {
	var image = 'images/green_star_32x32.png';
	new google.maps.Marker({position: initial_location,
		    map: MAP,
		    icon: image
		    });
    }
}

function update_markers (data, textStatus, jqXHR) {
    var sightings = data.sightings;
    if (! is_def (sightings))
	return;

    for (var i=0, len=sightings.length; i<len; i++) {
	var sighting = sightings[i];
	var elapsed_sec = (Date.now() - Date.parse(sighting.updated_at)) / 1000;
	var sighting_location = new google.maps.LatLng(sighting.gps_latitude,
						       sighting.gps_longitude);
	var image = 'images/pin.png';
	new google.maps.Marker({position: sighting_location,
		    map: MAP,
		    icon: image,
		    });
    }
}


function share_location_popup_callback () {
    $('#share_location_popup').popup('open');
    return;
}

var registration_callback = function(success_routine) {
    return function(data, textStatus, jqXHR) {
	if (is_def (data)) {
	    if (is_def (data.device_id)) {
		if (is_def (data.name) && is_def (data.email)) {
		    REGISTER_STATE = 1
		    $('#registration_form_spinner').hide();
		    display_in_div (data.message, 'registration_form_info', data.style);
		    success_routine();
		} else {
		    $('#registration_popup').popup('open')
		}
	    } else {
		display_error ("No device");
	    }
	} else {
	    display_error ("No data");
	}
    };
};

function call_when_registered (callback) {
    if (is_def (REGISTER_STATE)) {
	callback();
    } else {
	var device_id = get_cookie('device_id');
	if (is_def (device_id)) {
	    var request_parms = { method: 'get_registration',
				  device_id: device_id};
	    ajax_request (request_parms, registration_callback(callback));
	} else {
	    return;
	}
    }
}

function share_location_popup () {
    call_when_registered(share_location_popup_callback);
}

function share_location_callback (data, textStatus, jqXHR) {
    $('#share_location_form_spinner').hide();
    display_in_div (data.message, 'share_location_form_info', data.style);
    return;
}

function share_location () {
    var share_via = $("#share_location_form input[name='share_via']");
    var share_to = $("#share_location_form input[name='share_to']");

    if (share_to.length == 0) {
	display_in_div ("Please supply the address to send the share to",
			'share_location_form_info', 'color:red');
    }
    if (share_via == 'email' && ! share_to.match(/.+@.+/)) {
	display_in_div ("Email should be in the form <name>@<domain>",
			'share_location_form_info', 'color:red');
    }
    if (share_via == 'sms' && ! share_to.match(/^\d{10}$/)) {
	display_in_div ("The phone number (share to) must be 10 digits",
			'share_location_form_info', 'color:red');
    }
    $('#share_location_form_spinner').show();
    var params = $('#share_location_form').serialize();
    ajax_request (params, share_location_callback);
}

function view_beacon () {
    alert ("view_beacon");
}

function send_registration () {
    $('#registration_form_spinner').show();
    var params = $('#registration_form').serialize();
    ajax_request (params, registration_callback);
}