
// MARKERS = {device_id_1: {sighting: sighting_1, marker: marker_1, label: label_1}, 
//            device_id_2: {sighting: sighting_2, marker: marker_2, label: label_2}, ...
//           }
var MARKERS = {};
var DT;

var device_id_mgr = {
    device_id: null,
    phonegap:  null,
    init: function () {
	try {
	    device_id_mgr.device_id = device.uuid;
	}
	catch(err) {
	    console.log (err);
	    device_id_mgr.phonegap = false;
	    return;
	}
	device_id_mgr.phonegap = true;
    },
    get: function () {
	if (device_id_mgr.device_id) {
	    return (device_id_mgr.device_id);
	} else {
	    var cname = 'device_id';
	    var name = cname + "=";
	    var ca = document.cookie.split(';');
	    for(var i=0; i<ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1);
		if (c.indexOf(name) != -1) {
		    device_id_mgr.device_id = c.substring(name.length,c.length);
		    return device_id_mgr.device_id;
		}
	    }
	    return;
	}
    },
}

function update_map_canvas_pos () {
    var height = $('#geo_info').height();
    var header_title_height = height + 60;
    var content_height = height + 80;
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
	x_div.append ('<img src="https://eng.geopeers.com/images/x_black.png">');
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

var display_mgr = {
    new_orleans:   new google.maps.LatLng(29.9667,  -90.0500),
    san_francisco: new google.maps.LatLng(37.7833, -122.4167),
    new_york:      new google.maps.LatLng(40.7127,  -74.0059),
    us_center:     new google.maps.LatLng(39.8282,  -98.5795),

    geo_down:               null,
    message_displayed:      null,

    // used to prevent putting up the same message repeatedly
    // display_message prevents putting up the same message that is already visible
    // but this prevents opening a message box that the user just closed
    last_msg:               null,

    // The timeout warning is closed when the GPS is retrieved
    showed_timeout_warning: null,
    timeout_warning_md5:    null,

    // was the position available when the map was created
    // if not, pan to it as soon as the position becomes available
    initial_pan:            null,

    display_err: function(err) {
	// always run the panning check
	// if gmap has been created, but at (0,0), pan to a predefined location
	var map = $('#map_canvas').gmap('get','map');
	if (map) {
	    map_pos = map.getCenter();
	    if (map_pos.lat() == 0 && map_pos.lng() == 0) {
		map.panTo(display_mgr.us_center);
		$('#map_canvas').gmap('option', 'zoom', 4)
	    }
	}

	// some messages should only be displayed once
	if (display_mgr.message_displayed) {
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
	    // store the div id for this message so we can hide it when the position becomes available
	    display_mgr.timeout_warning_md5 = md5(msg);
	} else {
	    msg = "There was an unknown error getting your current location.";
	}
	display_mgr.geo_down = true;
	display_mgr.message_displayed = true;
	msg += "<br>You can view others, but you cannot share your location";
	display_mgr.last_msg = msg;
	display_message (msg, 'message_warning');
    },
    display_ok: function(position) {
	if (! display_mgr.initial_pan) {
	    display_mgr.initial_pan = true;
	    var map = $('#map_canvas').gmap('get','map');
	    var location = new google.maps.LatLng(position.coords.latitude,
						  position.coords.longitude);
	    map.panTo(location);
	}
	if (display_mgr.showed_timeout_warning) {
	    $('#'+display_mgr.timeout_warning_md5).hide();
	    display_mgr.showed_timeout_warning = null;
	    display_message ('Your GPS is now available','message_info');
	}
    }
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
	console.log ("lat=" + position.coords.latitude + ", lng=" + position.coords.longitude);
	var image = 'https://eng.geopeers.com/images/green_star_32x32.png';
	$('#map_canvas').gmap('addMarker', {marker_id: 'my_pos', icon: image, position: initial_location});
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

function popup_share_location_with_email () {
    $('#share_via option[value="email"]')
	.prop('selected', false)
	.filter('[value="email"]')
	.prop('selected', true);
    $('#share_to').val('scott@kaplans.com');
    $('#share_location_popup').popup('open');
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
	    'labelContent': label_text}).click(function() {popup_share_location_with_email()});
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



function ajax_request (request_parms, success_callback, failure_callback) {
    var url = "https://eng.geopeers.com/api";
    $.ajax({type:  "POST",
	    async: true,
	    url:   url,
	    data:  request_parms,
	  })
	.done(success_callback)
	.fail(failure_callback);
    return;
}


// SEND_POSITION

function send_position_callback (data, textStatus, jqXHR) {
    if (! data) {
	return;
    }
    console.log ("data="+data.inspect);
    return;
}

function send_position_failure_callback (jqXHR, textStatus, errorThrown) {
    console.log ("failed ajax call: "+textStatus+", errorThrown="+errorThrown);
}

function send_position_request (position) {
    if (! position)
	return;

    var device_id = device_id_mgr.get();
    console.log("sending device_id "+device_id+" position data");
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
    ajax_request (request_parms, send_position_callback, send_position_failure_callback);
    send_position_request.last_position = position;
    return;
}


// SHARE_LOCATION

function share_location_popup () {
    if (registration.status == 'REGISTERED') {
	if (display_mgr.geo_down) {
	    display_message (display_mgr.last_msg, 'message_warning');
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
    display_message(data.message, 'message_success');
    $('#share_location_popup').popup('close')
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
    ajax_request (params, share_location_callback, geo_ajax_fail_callback);
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

function get_positions () {
    var device_id = device_id_mgr.get();
    if (! device_id)
	return
    var request_parms = { method: 'get_positions',
			  device_id: device_id};
    ajax_request (request_parms, update_markers, geo_ajax_fail_callback);
    return;
}

function format_time (time) {
    // JS version of same routine in geo.rb on server

    // date will be in the browser's TZ
    var date = new Date(time);
    console.log (date.toString());

    var now = new Date();
    console.log (now.toString());

    var date_format_str, time_format_str;
    if (date.getFullYear() !== now.getFullYear()) {
	date_format_str = "MM d, yy";
	time_format_str = " 'at' h:mm tt";
    } else if (date.getMonth() !== now.getMonth()) {
	date_format_str = "MM d";
	time_format_str = " 'at' h:mm tt";
    } else if (date.getDate() !== now.getDate()) {
	date_format_str = "MM d";
	time_format_str = " 'at' h:mm tt";
    } else {
	time_format_str = "'Today at' h:mm tt";
    }

    var time_str;
    if (date_format_str) {
	time_str = $.datepicker.formatDate(date_format_str, date);
	time_str += $.datepicker.formatTime(time_format_str,
					    {hour: date.getHours(),
					    minute: date.getMinutes()});
    } else {
	time_str = $.datepicker.formatTime(time_format_str,
					  {hour: date.getHours(),
					   minute: date.getMinutes()});
    }
    var time_zone_str = /\((.*)\)/.exec(date.toTimeString())[0];
    var matches = time_zone_str.match(/\b(\w)/g);
    var time_zone_acronym = matches.join('');
    time_str += ' ' + time_zone_acronym;
    return (time_str);
}

function manage_shares_callback (data, textStatus, jqXHR) {
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
    head.append($('<th></th>').text('redeem_time'));
    head.append($('<th></th>').text('expire_time'));
    head.append($('<th></th>').text('Shared To'));
    head.append($('<th></th>').text('Used'));
    head.append($('<th></th>').text('Expires'));
    table.append($('<thead></thead>').append(head));
    var tbody = $('<tbody></tbody>');
    for(var i=0,len=data.shares.length; i<len; i++){
	var share = data.shares[i];

	var redeem_name = share.redeem_name ? share.redeem_name : '<Unopened>';
	var expires = share.expire_time ? format_time(share.expire_time) : 'Never';
	console.log (share.expire_time);
	var expire_time = new Date(share.expire_time);
	var now = Date.now();

	var expired;
	if (share.expire_time && (expire_time.getTime() < now)) {
	    expired = true;
	} else {
	    expired = false;
	}
	var share_to = share.name ? share.name + ' (' + share.share_to + ')' : share.share_to;
	var redeemed;
	if (share.redeem_time) {
	    var redeem_time = format_time(share.redeem_time);
	    if (share.redeem_name) {
		redeemed = 'By '+share.redeem_name+', '+redeem_time;
	    } else {
		redeemed = redeem_time;
	    }
	} else {
	    redeemed = "Not yet";
	}
	
	var row = $('<tr></tr>');
	if (expired) {
	    row.css('color', 'red');
	    row.css('text-decoration', 'line-through');
	}
	row.append($('<td></td>').text(share.redeem_time));
	row.append($('<td></td>').text(share.expire_time));
	row.append($('<td></td>').text(share_to));
	row.append($('<td></td>').text(redeemed));
	row.append($('<td></td>').text(expires));
	tbody.append(row);
    }
    table.append(tbody);

    $('#manage_info').replaceWith(table);
    if (!  $.fn.dataTable.isDataTable( '#manage_table' ) ) {
	DT = $('#manage_table').DataTable( {
		retrieve:     true,
		aoColumnDefs: [ { "iDataSort": 0, "aTargets": [ 3 ] },
	                        { "iDataSort": 1, "aTargets": [ 4 ] },
				],
		order:        [ 4, 'desc' ]
	    } );
	DT.column(0).visible(false);
	DT.column(1).visible(false);
    }
    $('#manage_popup').popup('open');
    
}

function manage_shares () {
    var device_id = device_id_mgr.get();
    if (! device_id)
	return
    var request_parms = { method: 'get_shares',
			  device_id: device_id,
    };
    ajax_request (request_parms, manage_shares_callback, geo_ajax_fail_callback);
    return;
}

function run_position_function (post_func) {
    // post_func should be prepared to be called with 0 (gps failed) or 1 (position) parameter
    if(navigator.geolocation) {
	navigator.geolocation.getCurrentPosition(function (position) {post_func(position);
		                                                      display_mgr.display_ok(position)},
						 function (err)      {post_func();
						                      display_mgr.display_err(err)},
                                                 {timeout:3000, enableHighAccuracy: true});
    }
    return;
}

function registration_callback (data, textStatus, jqXHR) {
    $('#registration_form_spinner').hide();
    if (data) {
	registration.status = 'REGISTERED';
	display_message(data.message, 'message_success');
	$('#registration_popup').popup('close')
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
    ajax_request (params, registration_callback, geo_ajax_fail_callback);
}

var registration = {
    // registration.init() launches request to get registration status
    // manages the callback and the status variable
    status : null,
    init: function () {
	if (registration.status == 'REGISTERED' || registration.status == 'CHECKING')
	    return;
	var device_id = device_id_mgr.get();
	if (device_id) {
	    var request_parms = { method: 'get_registration',
				  device_id: device_id};
	    ajax_request (request_parms, registration.callback, geo_ajax_fail_callback);
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

function update_current_pos () {
    run_position_function (function(position) {
	    if (! position) {
		return;
	    }
	    $('#map_canvas').gmap('find', 'markers',
				  { 'property': 'marker_id', 'value': 'my_pos' },
				  function(marker, found) {
				      if (found) {
					  var my_pos = new google.maps.LatLng(position.coords.latitude,
									      position.coords.longitude)
					  marker.setPosition(my_pos);
				      }
				  });
	});
}

function heartbeat () {
    // things that should happen periodically
    var period_minutes = 1;

    run_position_function (function(position) {
	    send_position_request (position);
	});

    // refresh the sightings for our shares
    get_positions();

    update_current_pos();

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

function init () {
    device_id_mgr.init ();

    if (device_id_mgr.phonegap) {
	// Wait for device API libraries to load
	document.addEventListener("deviceready", init_background_gps, false);
    }

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
    update_current_pos();
}

$(document).ready(function(e,data){
	init();
    });
