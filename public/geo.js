
// MARKERS = {device_id_1: {sighting: sighting_1, marker: marker_1, label: label_1}, 
//            device_id_2: {sighting: sighting_2, marker: marker_2, label: label_2}, ...
//           }
var MARKERS = {};

function update_map_canvas_pos () {
    var height = $('#geo_info').height();
    var header_title_height = height + 50;
    var content_height = height + 70;
    $('#header_title').css('height', header_title_height+'px');
    $('#content').css('top', content_height+'px');
}

function display_message (message, css_class) {
    if (! message) {
	return;
    }
    var msg_id = md5(message);
    if ($('#'+msg_id).length) {
	// we already got this message, just make sure it is visible
	$('#'+msg_id).show();
    } else {
	// create new divs - message and close button
	// append to geo_info
	var onclick_cmd = "$('#"+msg_id+"').hide(); update_map_canvas_pos()";
	var x_div = $('<div></div>')
	    .attr('onclick', onclick_cmd)
	    .css('position','relative')
	    .css('right','16px')
	    .css('top','40px')
	    .css('text-align','right');
	x_div.append ('<img src="/images/x_black.png">');
	var msg_div = $('<div></div>')
	    .html(message)
	    .addClass(css_class);
	var wrapper_div = $('<div></div>').attr('id',msg_id);
	wrapper_div.append(x_div);
	wrapper_div.append(msg_div);
	$('#geo_info').append(wrapper_div);
    }
    update_map_canvas_pos();
}

function display_in_div (msg, div_id, style) {
    if (! div_id) {
	return;
    }
    if (typeof msg === 'object') {
	msg = JSON.stringify (msg);
    }
    $('#'+div_id).html(msg);
    if (style) {
	$('#'+div_id).css(style);
    }
    return;
}

var no_geo_message = {
    new_orleans:   new google.maps.LatLng(29.9667,  -90.0500),
    san_francisco: new google.maps.LatLng(37.7833, -122.4167),
    new_york:      new google.maps.LatLng(40.7127,  -74.0059),
    us_center:     new google.maps.LatLng(39.8282,  -98.5795),
    last_msg:      null,
    geo_down:      null,
    message_displayed: null,
    showed_timeout_warning: null,
    display: function(err) {
	// always run the panning check
	// if gmap has been created, but at (0,0), pan to a predefined location
	var map = $('#map_canvas').gmap('get','map');
	if (map) {
	    map_pos = map.getCenter();
	    if (map_pos.lat() == 0 && map_pos.lng() == 0) {
		map.panTo(no_geo_message.us_center);
		$('#map_canvas').gmap('option', 'zoom', 4)
	    }
	}

	// some messages should only be displayed once
	if (no_geo_message.message_displayed) {
	    return;
	}

	console.log (err);
	var msg;
	if        (err.code === 1) {
	    msg = "You have blocked your current location.";
	} else if (err.code === 2) {
	    msg = "Your current location is not available.";
	} else if (err.code === 3) {
	    msg = "Getting your current location timed out.  We'll keep trying.";
	    no_geo_message.showed_timeout_warning = 1;
	} else {
	    msg = "There was an unknown error getting your current location.";
	}
	no_geo_message.geo_down = 1;
	no_geo_message.message_displayed = 1;
	msg += "<br>You can view others, but you cannot share your location";
	no_geo_message.last_msg = msg;
	display_message (msg, 'message_warning');
    },
}

//
// MAP STUFF
//

function create_map (position) {
    var initial_location;
    var zoom = 13;
    if (position) {
	initial_location = new google.maps.LatLng(position.coords.latitude,
						  position.coords.longitude);
    }
    $('#map_canvas').gmap({center: initial_location, zoom: zoom});
    if (position) {
	var image = 'images/green_star_32x32.png';
	$('#map_canvas').gmap('addMarker', {icon: image, position: initial_location});
    }
}

function create_time_elem_str (num, unit) {
    if (num === 0) {    
	return ;
    }
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
    var label_text = '<span style="text-align:center;font-size:20px;font-weight:bold;color:#453345"><div>' + sighting.name + '</div><div style="font-size:16px">' + elapsed_str + '</div></span>';
    return (label_text);
}

function update_marker_view (marker_info) {
    var sighting = marker_info.sighting;
    var sighting_location = new google.maps.LatLng(sighting.gps_latitude,
						   sighting.gps_longitude);
    var label_text = create_label_text (sighting);
    $('#map_canvas').gmap('find', 'markers',
			  { 'property': 'device_id', 'value': sighting.device_id },
			  function(marker, found) {
			      if (found) {
				  marker.labelContent = label_text;
				  marker.setPosition(sighting_location);
			      }
			  });
    return;
}

function create_marker (sighting) {
    var label_text = create_label_text (sighting);
    marker = $('#map_canvas').gmap('addMarker', {
	    'device_id':    sighting.device_id,
	    'position':     new google.maps.LatLng(sighting.gps_latitude,sighting.gps_longitude),
	    'marker':       MarkerWithLabel,
	    'icon':         '/images/pin_wings.png',
	    'labelAnchor':  new google.maps.Point(60, 0),
	    'labelContent': label_text});
    return ({marker: marker});
}

function update_markers (data, textStatus, jqXHR) {
    if (! data)
	return;
    var sightings = data.sightings;
    if (! sightings)
	return;

    // update MARKERS with whatever sightings are received (position change)
    for (var i=0, len=sightings.length; i<len; i++) {
	var sighting = sightings[i];
	if (! MARKERS[sighting.device_id]) {
	    MARKERS[sighting.device_id] = create_marker (sighting);
	}
	// and hold the most recent sighting to keep this marker's label up to date
	MARKERS[sighting.device_id].sighting = sighting;
    }

    // update the views of all the markers
    // so we update the elapsed time of markers where the position has not changed
    for (var device_id in MARKERS) {
	update_marker_view (MARKERS[device_id]);
    }

    var bounds = new google.maps.LatLngBounds ();
    for (var device_id in MARKERS) {
	var sighting = MARKERS[device_id].sighting;
	var sighting_location = new google.maps.LatLng(sighting.gps_latitude,
						       sighting.gps_longitude);
	bounds.extend (sighting_location);
    }
    var map = $('#map_canvas').gmap('get','map');
    map.fitBounds (bounds);
    var zoom = map.getZoom();
    // if we only have one marker, fitBounds zooms to maximum.
    // Back off to max_zoom
    var max_zoom = 16;
    if (zoom > max_zoom) {
	$('#map_canvas').gmap('option', 'zoom', max_zoom);
    }
    //google.maps.event.trigger(map, 'resize');
    return;
}

function share_location_popup () {
    if (registration.status == 'REGISTERED') {
	if (no_geo_message.geo_down) {
	    display_message (no_geo_message.last_msg, 'message_warning');
	} else {
	    $('#share_location_popup').popup('open');
	}
    } else if (! registration.status ||
	       registration.status == 'NOT REGISTERED') {
	$('#registration_popup').popup('open');
    } else if (registration.status == 'CHECKING') {
	display_message ('Checking your registration status.  Try again in a few seconds', 'message_warning');
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

function geo_ajax_success_callback (data, textStatus, jqXHR) {
    if (data.message) {
	display_message (data.message, 'message_info');
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
    display_message (error_html, 'message_error');
    $('#registration_form_spinner').hide();
    $('#share_location_form_spinner').hide();
    return;
}

function ajax_request (request_parms, success_callback) {
    var url = "/api";
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
    if (! position)
	return;

    var device_id = get_cookie('device_id');
    if (! device_id)
	return;

    // don't send the same co-ordinates again
    if (send_position_request.last_position &&
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
    if (! device_id)
	return
    var request_parms = { method: 'get_positions',
			  device_id: device_id};
    ajax_request (request_parms, update_markers);
    return;
}

function format_expire_time (expire_time) {
    // JS version of same routine in geo.rb on server
    var expire_date = new Date(expire_time);
    var now = new Date();
    var date_format_str, time_format_str;
    if (expire_date.getFullYear() !== now.getFullYear()) {
	date_format_str = "MM d, yy";
	time_format_str = " 'at' h:mm tt";
    } else if (expire_date.getMonth() !== now.getMonth()) {
	date_format_str = "MM d";
	time_format_str = " 'at' h:mm tt";
    } else if (expire_date.getDate() !== now.getDate()) {
	date_format_str = "MM d";
	time_format_str = " 'at' h:mm tt";
    } else {
	time_format_str = "'Today at' h:mm tt";
    }

    var expires;
    if (date_format_str) {
	expires = $.datepicker.formatDate(date_format_str, expire_date);
	expires += $.datepicker.formatTime(time_format_str,
					   {hour: expire_date.getHours(),
					    minute: expire_date.getMinutes()});
    } else {
	expires += $.datepicker.formatTime(time_format_str,
					   {hour: expire_date.getHours(),
					    minute: expire_date.getMinutes()});
    }
    return (expires);
}

function manage_beacons_callback (data, textStatus, jqXHR) {
    // create markup for a table, loaded with data
    // table is of the form:
    // <table>
    //   <thead>
    //     <tr><th>...</th><th>...</th>...
    //   </thead>
    //   <tbody>
    //     <tr><td>...</td><td>...</td>...
    //   </tbody>
    // </table>
    var table = $('<table></table>').attr('id','manage_table').addClass('display');
    var head = $('<tr></tr>');
    head.append($('<th></th>').text('Shared Via'));
    head.append($('<th></th>').text('Shared To'));
    head.append($('<th></th>').text('Name'));
    head.append($('<th></th>').text('Status'));
    head.append($('<th></th>').text('Expires'));
    table.append($('<thead></thead>').append(head));
    var tbody = $('<tbody></tbody>');
    for(var i=0,len=data.beacons.length; i<len; i++){
	var beacon = data.beacons[i];
	var status = beacon.created_at === beacon.activate_time ? 'Unopened' : 'Active';
	var expires;
	if (beacon.expire_time) {
	    expires = format_expire_time(beacon.expire_time);
	} else {
	    expires = 'Never';
	}
	var row = $('<tr></tr>');
	row.append($('<td></td>').text(beacon.share_via));
	row.append($('<td></td>').text(beacon.share_to));
	row.append($('<td></td>').text(beacon.name));
	row.append($('<td></td>').text(status));
	row.append($('<td></td>').text(expires));
	tbody.append(row);
    }
    table.append(tbody)

    $('#manage_info').replaceWith(table);
    $('#manage_table').dataTable();
    $('#manage_popup').popup('open');
    
}

function manage_beacons () {
    var device_id = get_cookie('device_id');
    if (! device_id)
	return
    var request_parms = { method: 'get_beacons',
			  device_id: device_id};
    ajax_request (request_parms, manage_beacons_callback);
    return;
}

function manage_display () {
    if (no_geo_message.showed_timeout_warning) {
	display_message ('Your GPS is now available','message_info');
	no_geo_message.showed_timeout_warning = null;
    }
}

function run_position_function (post_func) {
    if(navigator.geolocation) {
	navigator.geolocation.getCurrentPosition(function (position) {post_func(position); manage_display()},
						 function (err) {post_func();
								 no_geo_message.display(err)},
                                                 {timeout:3000});
    }
    return;
}

function registration_callback (data, textStatus, jqXHR) {
    $('#registration_form_spinner').hide();
    if (data) {
	registration.status = 'REGISTERED';
	display_in_div (data.message, 'registration_form_info', data.style);
    } else {
	display_in_div ('No data', 'registration_form_info', {color:'red'});
    }
    return;
}

function validate_registration_form () {
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
    return 1;
}

function send_registration () {
    if (! validate_registration_form()) {
	return;
    }
    $('#registration_form_spinner').show();
    var params = $('#registration_form').serialize();
    ajax_request (params, registration_callback);
}

var registration = {
    // registration.init() launches request to get registration status
    // manages the callback and the status variable
    status : null,
    init: function () {
	if (registration.status == 'REGISTERED' || registration.status == 'CHECKING')
	    return;
	var device_id = get_cookie('device_id');
	if (device_id) {
	    var request_parms = { method: 'get_registration',
				  device_id: device_id};
	    ajax_request (request_parms, registration.callback);
	    // while the request/response is in the air, we're in an indeterminant state
	    // Anyone who cares about the registration status should assume that the popup 
	    // has been filled out and is in the air.
	    // So don't pop it up again
	    registration.status = 'CHECKING';
	}
    },
    callback: function (data, textStatus, jqXHR) {
	if (data && data.device_id) {
	    if (data.name && data.email) {
		registration.status = 'REGISTERED';
	    } else {
		registration.status = 'NOT REGISTERED';
	    }
	} else {
	    registration.status = null;
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
    // things that should happen periodically
    period_minutes = 1;

    // tell the server where we are
    run_position_function (function(position) {
	    send_position_request (position);
	});

    // refresh the sightings for our beacons
    get_positions();

    // if we get here, schedule the next iteration
    setTimeout(heartbeat, period_minutes * 60 * 1000);
    return;
}

function display_alert (alert_msg) {
    if (! alert_msg) {
	alert_msg = getParameterByName('alert');
    }
    if (! alert_msg) {
	return;
    }

    $('#alert_popup').popup('open');
    display_in_div (alert_msg, 'alert_form_info', {color:'red'});
    return;
}

$(document).ready(function(e,data){
	run_position_function (function(position) {create_map(position)});

	// sets registeration.status
	// used by popups to see if they should put up the registration screen instead
	registration.init();

	// server has redirected to us and has a message to popup
	display_message(getParameterByName('alert'), 'message_error');
	
	// This is a bad hack.
	// If the map isn't ready when the last display_message fired, the reposition will be wrong
	setTimeout(function(){update_map_canvas_pos()}, 500);

	heartbeat();
    });
