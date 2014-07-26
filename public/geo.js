var REGISTER_STATE;
var MAP;

// MARKERS = {device_id_1: {sighting: sighting_1, marker: marker_1, label: label_1}, 
//            device_id_2: {sighting: sighting_2, marker: marker_2, label: label_2}, ...
//           }
var MARKERS = {};
var POSITION;

//
// MAP STUFF
//

function create_map (position) {
    var initial_location;
    var zoom_level = 13;
    if (is_def (position)) {
	initial_location = new google.maps.LatLng(position.coords.latitude,
						  position.coords.longitude);
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

// Define the overlay, derived from google.maps.OverlayView
function Label(opt_options) {
    this.setValues(opt_options);

    var span = this.span_ = document.createElement('span');
    span.style.cssText = 'position: relative; left: -50%; font-size:20px; color:red';

    var div = this.div_ = document.createElement('div');
    div.appendChild(span);
    div.style.cssText = 'position: absolute; display: none';
};
Label.prototype = new google.maps.OverlayView;


// Implement onAdd
Label.prototype.onAdd = function() {
    var pane = this.getPanes().overlayImage;
    pane.appendChild(this.div_);

    // Ensures the label is redrawn if the text or position is changed.
    var me = this;
    this.listeners_ = [
		       google.maps.event.addListener(this, 'position_changed', function() { alert('position_changed'); me.draw(); }),
		       google.maps.event.addListener(this, 'visible_changed', function() { alert('visible_changed'); me.draw(); }),
		       google.maps.event.addListener(this, 'clickable_changed', function() { alert('clickable_changed'); me.draw(); }),
		       google.maps.event.addListener(this, 'text_changed', function() { alert('text_changed'); me.draw(); }),
		       google.maps.event.addListener(this, 'zindex_changed', function() { alert('zindex_changed'); me.draw(); }),
		       google.maps.event.addDomListener(this.div_, 'click', function() { 
			       if (me.get('clickable')) {
				   google.maps.event.trigger(me, 'click');
			       }
			   })
		       ];
};


// Implement onRemove
Label.prototype.onRemove = function() {
    this.div_.parentNode.removeChild(this.div_);


    // Label is removed from the map, stop updating its position/text
    for (var i = 0, I = this.listeners_.length; i < I; ++i) {
	google.maps.event.removeListener(this.listeners_[i]);
    }
};


// Implement draw
Label.prototype.draw = function() {
    var projection = this.getProjection();
    if (! projection) {
	return;
    }
    var position = projection.fromLatLngToDivPixel(this.get('position'));
    if (! position) {
	return;
    }

    var div = this.div_;
    if (! div) {
	return;
    }
    div.style.left = position.x + 'px';
    div.style.top = position.y + 'px';

    div.style.display = 'block';

    var zIndex = this.get('zIndex');
    div.style.zIndex = zIndex;

    var text = this.get('text')
    this.span_.innerHTML = text;
};

function create_time_elem_str (num, unit) {
    var str = num + ' ' + unit;
    if (num > 1) {
	str += 's';
    }
    return (str);
}

function create_elapsed_str (sighting) {
    var elapsed_sec = Math.round ((Date.now() - Date.parse(sighting.sighting_time)) / 1000);
    if (elapsed_sec < 60) {
	elapsed_str = elapsed_sec + ' seconds';
    } else {
	var elapsed_min = Math.round (elapsed_sec / 60);
	if (elapsed_min < 60) {
	    elapsed_str = create_time_elem_str (elapsed_min, 'minute');
	} else {
	    var elapsed_hr = Math.round (elapsed_min / 60);
	    elapsed_min = elapsed_min % 60;
	    if (elapsed_hr < 24) {
		elapsed_str = create_time_elem_str (elapsed_hr, 'hour');
		elapsed_str += ' ';
		elapsed_str += create_time_elem_str (elapsed_min, 'minute');
	    } else {
		var elapsed_day = Math.round (elapsed_hr / 24);
		elapsed_hr = elapsed_hr % 24;
		elapsed_str = create_time_elem_str (elapsed_day, 'day');
		elapsed_str += ' ';
		elapsed_str += create_time_elem_str (elapsed_hr, 'hour');
	    }
	}
    }
    elapsed_str = '('+elapsed_str+' ago)';
    return (elapsed_str);
}

function create_label_text (sighting) {
    var elapsed_str = create_elapsed_str (sighting);
    var label_text = '<span style="text-align:center"><div>' + sighting.name + '</div><div style="font-size:16px">' + elapsed_str + '</div></span>';
    return (label_text);
}

function update_marker_view (marker_info) {
    var label_text = create_label_text (marker_info.sighting);
    marker_info.marker.text = label_text;
    var sighting_location = new google.maps.LatLng(marker_info.sighting.gps_latitude,
						   marker_info.sighting.gps_longitude);
    marker_info.marker.position = sighting_location;

    //    marker_info.marker.draw();
    return;
}

function create_marker (sighting) {
    var image = 'images/pin.png';
    var marker = new google.maps.Marker({map:       MAP,
					 icon:      image,
					 optimized: false,
					 text:      undefined,
					 position:  undefined,
	});
    var label = new Label({
	    map: MAP,
	});
    label.bindTo('zIndex', marker);
    label.bindTo('position', marker);
    label.bindTo('text', marker);
    return ({marker:marker, label:label});
}

function update_markers (data, textStatus, jqXHR) {
    var sightings = data.sightings;
    if (! is_def (sightings))
	return;

    // update MARKERS with whatever sightings are received (position change)
    for (var i=0, len=sightings.length; i<len; i++) {
	var sighting = sightings[i];
	if (! MARKERS[sighting.device_id]) {
	    MARKERS[sighting.device_id] = create_marker (sighting);
	}
	MARKERS[sighting.device_id].sighting = sighting;
    }

    // update the views of all the markers
    // so we update the elapsed time of markers where the position has not changed
    for (var device_id in MARKERS) {
	update_marker_view (MARKERS[device_id]);
    }
    return;
}

function share_location_popup () {
    if (registration.status == 'REGISTERED') {
	$('#share_location_popup').popup('open');
    } else if (! is_def (registration.status) ||
	       registration.status == 'NOT REGISTERED') {
	$('#registration_popup').popup('open');
    } else if (registration.status == 'CHECKING') {
	display_alert ('Checking your registration status.  Try again in a few seconds', {color: 'red'});
    } else {
	// Not sure what's going on, try registration
	$('#registration_popup').popup('open');
    }
    return;
}

function share_location_callback (data, textStatus, jqXHR) {
    $('#share_location_form_spinner').hide();
    display_in_div (data.message, 'share_location_form_info', data.style);
    return;
}

function share_location () {
    var share_via = $("#share_via").val();
    var share_to = $("#share_to").val();

    if (share_to.length == 0) {
	display_in_div ("Please supply the address to send your share to",
			'share_location_form_info', {color:'red'});
	return;
    }
    if (share_via == 'email' && ! share_to.match(/.+@.+/)) {
	display_in_div ("Email should be in the form 'fred@company.com'",
			'share_location_form_info', {color:'red'});
	return;
    }
    if (share_via == 'sms' && ! share_to.match(/^\d{10}$/)) {
	display_in_div ("The phone number (share to) must be 10 digits",
			'share_location_form_info', {color:'red'});
	return;
    }
    $('#share_location_form_spinner').show();
    var params = $('#share_location_form').serialize();
    var tz = jstz.determine();
    params += '&tz='+tz.name();
    ajax_request (params, share_location_callback);
}

function is_def (v) {
    var ret = ((v != undefined) && (v != null) && (v != ""))
    return (ret);
}

function display_alert (msg, style) {
    $('#alert_popup').popup('open');
    display_in_div (msg, 'alert_form_info', style);
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
    var url = "http://www.geopeers.com:4567/api";
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
    if (! is_def (position))
	return;

    var device_id = get_cookie('device_id');
    if (! is_def (device_id))
	return;

    // don't send the same co-ordinates again
    if (is_def (send_position_request.last_position) &&
    	(send_position_request.last_position.coords.longitude == position.coords.longitude) &&
    	(send_position_request.last_position.coords.latitude == position.coords.latitude))
    	return;

    var request_parms = { gps_longitude: position.coords.longitude,
			  gps_latitude:  position.coords.latitude,
			  method:        'send_position',
			  device_id:     device_id,
    };
    ajax_request (request_parms, geo_ajax_success_callback);
	send_position_request.last_position = position;
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

function manage_beacons_callback (data, textStatus, jqXHR) {
}

function manage_beacons () {
    var device_id = get_cookie('device_id');
    if (! is_def (device_id))
	return
    var request_parms = { method: 'get_beacons',
			  device_id: device_id};
    ajax_request (request_parms, manage_beacons_callback);
    return;
}

function run_position_function (post_func) {
    if(navigator.geolocation) {
	navigator.geolocation.getCurrentPosition(function(position) {post_func(position)},
						 function(err) {});
    }
    return;
}

function registration_callback (data, textStatus, jqXHR) {
    $('#registration_form_spinner').hide();
    if (is_def (data)) {
	registration.status = 'REGISTERED';
	display_in_div (data.message, 'registration_form_info', data.style);
    } else {
	display_in_div ('No data', 'registration_form_info', {color:'red'});
    }
    return;
}

function send_registration () {
    var name = $('#registration_form #name').val();
    if (name.length == 0) {
	display_in_div ("Please supply your name",
			'registration_form_info', {color:'red'});
	return;
    }
    var email = $('#registration_form #email').val();
    if (email.length == 0) {
	display_in_div ("Please supply your email",
			'registration_form_info', {color:'red'});
	return;
    }
    if (! email.match(/.+@.+/)) {
	display_in_div ("Email should be in the form 'fred@company.com'",
			'registration_form_info', {color:'red'});
	return;
    }


    $('#registration_form_spinner').show();
    var params = $('#registration_form').serialize();
    ajax_request (params, registration_callback);
}

var registration = {
    status : undefined,
    init: function () {
	if (registration.status == 'REGISTERED' || registration.status == 'CHECKING')
	    return;
	var device_id = get_cookie('device_id');
	if (is_def (device_id)) {
	    var request_parms = { method: 'get_registration',
				  device_id: device_id};
	    registration.status = 'CHECKING';
	    ajax_request (request_parms, registration.callback);
	}
    },
    callback: function (data, textStatus, jqXHR) {
	if (is_def (data) &&
	    is_def (data.device_id)) {
	    if (is_def (data.name) &&
		is_def (data.email)) {
		registration.status = 'REGISTERED';
	    } else {
		registration.status = 'NOT REGISTERED';
	    }
	} else {
	    registration.status = undefined;
	}
    },
}

function getParameterByName(name) {
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
    var regex = new RegExp("[\\?&]" + name + "=([^&#]*)"),
	results = regex.exec(location.search);
    return results == null ? "" : decodeURIComponent(results[1].replace(/\+/g, " "));
}

function heartbeat () {
    period_minutes = 1;
    run_position_function (function(position) {
	    send_position_request (position);
	});
    get_positions();
    setTimeout(heartbeat, period_minutes * 60 * 1000);
    return;
}

$(document).ready(function(e,data){
	run_position_function (function(position) {
		create_map(position);
	    });
	registration.init();
	var alert = getParameterByName('alert');
	if (is_def (alert))
	    display_alert (alert);
	heartbeat();
    });
