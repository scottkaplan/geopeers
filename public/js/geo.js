"use strict"

//
// Utils
//

function get_client_type () {
    var user_agent = navigator.userAgent;
    console.log (user_agent);
    if (/android/i.exec(user_agent)) {
	return ('android');
    } else if (/iphone/i.exec(user_agent) ||
	       /ipad/i.exec(user_agent)) {
	return ('ios');
    } else {
	return ('web');
    }
}

function get_parms (url) {
    var parm_str = url.match (/^geopeers:\/\/api\?(.*)/);
    if (! parm_str) {
	return;
    }
    console.log (parm_str[0]);
    var parm_strs = parm_str[0].split('&');
    var parms = {};
    for (var i=0; i<parm_strs.length; i++) {
	var key_val = parm_strs[i].split('=');
	parms[key_val[0]] = key_val[1];
    }
    console.log (parms);
    return (parms);
}

function host () {
    var server = $('#geopeers_config').attr('server');
    return (server);
}

function is_phonegap () {
    return (window.location.href.match (/^file:/));
}

function getParameterByName(name) {
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
    var regex = new RegExp("[\\?&]" + name + "=([^&#]*)"),
	results = regex.exec(location.search);
    return results == null ? "" : decodeURIComponent(results[1].replace(/\+/g, " "));
}

function have_native_app () {
    // is the native app installed on this device?
    if (registration.reg_info &&
	registration.reg_info.device &&
	registration.reg_info.device.xdevice_id) {
	return (true);
    } else {
	return (false);
    }
}

function change_orientation (e) {
    if (e.orientation === 'landscape') {
	console.log ('landscape');
	$('#manage_msg').empty();
    } else {
	console.log ('portrait');
    }
}

function is_orientation (requested_orientation) {
    var orientation = window.orientation;
    if (typeof(orientation) === 'undefined') {
	return (false);
    } else {
	if (orientation ==  90 ||
	    orientation == -90) {
	    return (requested_orientation == 'landscape');
	} else {
	    return (requested_orientation == 'portrait');
	}
    }
}

function if_else_native (is_native_function, is_not_native_function) {
    if (is_phonegap()) {
	if (is_native_function) {
	    is_native_function();
	}
    } else {
	if (is_not_native_function) {
	    is_not_native_function();
	}
    }
}

function display_alert_message (alert_method, message) {
    // this is called either
    // 1) 'alert_method=<alert_method>' as a URL parm
    // 2) called as JS, typically injected at the bottom of index.html

    alert_method = alert_method || getParameterByName('alert_method');
    if (! alert_method) {
	return;
    }
    var message_type = getParameterByName('message_type') ? getParameterByName('message_type') : 'message_error';
    var message;
    switch (alert_method) {
    case "NO_NATIVE":
	message = "There is no native app available for this device";
	message_type = 'message_warning';
	break;
    case "SUPPORT_CONTACTED":
	message = "There was a problem with your request.  Support has been contacted.";
	message_type = 'message_error';
	break;
    case "CRED_INVALID":
	message = "That credential is not valid.  You can't view the location.  You can still use the other features of GeoPeers";
	message_type = 'message_warning';
	break;
    case "DEVICE_ADDED":
        message = getParameterByName('auth_key') + " is used by " + getParameterByName('account_name') + ".  Your device has been added to this account.";
	message_type = 'message_info';
	break;
    case "DEVICE_REGISTERED":
        message = getParameterByName('account_name') + " has been registered.";
	message_type = 'message_success';
	break;
    case "SHARES_XFERED":
	message = "We transferred your shared locations to the native app";
	message += "<p>Switch to the native app from the main menu";
	message_type = 'message_success';
	break;
    case "SHARES_XFERED_COUNTDOWN":
        message = "We transferred your shared locations to the native app";
	message += "<p><div class='message_button' onclick='native_app_redirect_wrapper()'><div class='message_button_text'>Go to native app</div></div>";
	message += "<p><span>You will be switched back automatically in </span>";
	message += "<span id='countdown_native_app_redirect' style='font-size:18px'>11</span>";
	message += "<script>device_id_bind.countdown_native_app_redirect()</script>";
	message_type = 'message_success';
	break;
    case "SHARES_XFERED_MSG":
	if (! message) {
	    message = getParameterByName('message');
	}
	message += "<p>You can switch to the native app from the main menu";
	message_type = 'message_warning';
	break;
    }
    var message_div_id = display_message(message, message_type, 'geo_info');
    return (message_div_id);
}

function hide_message_div (msg_id) {
    $('#'+msg_id).hide();
    // map_mgr.resize();
}

function create_message_div (message, css_class, msg_id) {
    // create new divs - message and close button
    var onclick_cmd = "hide_message_div('"+msg_id+"')";
    var x_div = $('<div></div>')
	.attr('onclick', onclick_cmd)
	.addClass('x_div');
    x_div.append ('<img src="images/x_black.png">');
    var msg_div = $('<div></div>')
	.html(message)
	.addClass(css_class);
    var wrapper_div = $('<div></div>').attr('id',msg_id);
    wrapper_div.append(x_div);
    wrapper_div.append(msg_div);
    return (wrapper_div);
}

function display_message (message, css_class, target_div) {
    if (! message) {
	return;
    }
    var msg_id = md5(message);
    if ($('#'+msg_id).length) {
	// we already got this message
	if ($('#'+msg_id).is(":hidden")) {
	    // it's hidden, show it
	    $('#'+msg_id).show()
	} else{
	    // It is already visible, "flash" it
	    $('#'+msg_id).fadeOut(10).fadeIn(100);
	}
    } else {
	var msg_div = create_message_div (message, css_class, msg_id);
	$('#'+target_div).append(msg_div);
    }
    return (msg_id);
}

function form_request (form, extra_params, success_callback, failure_callback) {
    var params_array = form.serializeArray();
    // rearrange from:
    //   [ { name: n1, value: v1 }, { name: n2, value: v2 }, ... ]
    // to:
    //   { n1: v1, n2: v2, ...}
    var params = {};
    $.each(params_array, function() {
	    if (params[this.name] !== undefined) {
		if (!params[this.name].push) {
		    params[this.name] = [params[this.name]];
		}
		params[this.name].push(this.value || '');
	    } else {
		params[this.name] = this.value || '';
	    }
	});

    // merge the extra parameters (non-form variables)
    $.extend (params, extra_params);

    // always send device_id
    params['device_id'] = params['device_id'] ? params['device_id'] : device_id_mgr.get();
    console.log (params['device_id']);

    ajax_request (params, success_callback, failure_callback);
}

function form_request_callback (data, spinner_id, form_info_id) {
    $('#'+spinner_id).hide();
    var css_class = data.css_class ? data.css_class : 'message_success'
    if (data.page_message) {
	// show message on this page
	display_message(data.page_message, css_class, form_info_id);
    } else {
	// show message on index page
	page_mgr.switch_page ('index');
	display_message(data.message, css_class, 'geo_info');

	// clear any old error messages
	$('#'+form_info_id).empty();
    }
    return;
}

function ajax_request (request_parms, success_callback, failure_callback) {
    // phonegap runs from https://geopeers.com
    // we now allow xdomain from that URL
    var url = "https://" + host() + "/api";
    $.ajax({type:  "POST",
	    async: true,
	    url:   url,
	    data:  request_parms,
	  })
	.done(success_callback)
	.fail(failure_callback);
    console.log ("ajax_request:"+JSON.stringify(request_parms));
    return;
}

function geo_ajax_fail_callback (data, textStatus, jqXHR) {
    var error_html;
    if (typeof (data.error) === 'string') {
	error_html = data.error_html ? data.error_html : data.error;
    } else if (data.responseJSON) {
	error_html = data.responseJSON.error_html ? data.responseJSON.error_html : data.responseJSON.error;
    }
    display_message (error_html, 'message_error', 'geo_info');
    // Don't bother trying to figure out who failed
    // turn off all the spinners
    $('.page_spinner').hide();
    return;
}

function gps_position_succeeded (post_func, position) {
    my_pos.update_position (position);
    post_func(position);
    display_mgr.display_ok(position);
    return;
}

function gps_position_failed (post_func, err) {
    if (marker_mgr.current_position &&
	device_id_mgr.phonegap) {
	console.log (marker_mgr.current_position);
	post_func(marker_mgr.current_position);
    } else {
	post_func();
	console.log ("No position");
	display_mgr.display_err(err);
    }
    return;
}

function run_position_function (post_func) {
    // post_func should be prepared to be called with 0 (gps failed) or 1 (position) parameter
    var options = {timeout:3000, enableHighAccuracy: true};
    if(navigator.geolocation) {
	navigator.geolocation.getCurrentPosition (
						  function (position) {
						      gps_position_succeeded (post_func, position);
							  },
						  function (err) {
						      gps_position_failed (post_func, err);
							  },
						  options);
    }
    return;
}

var page_mgr = {
    init: function () {
	// install an event handler to clean up the map when we return to the index page
	$( document ).on( "pagecontainerchange", function( event, ui ) {
	    var page_id = ui.toPage.attr('id');
	    console.log (page_id);
	    // giant hack to fix JQM's habit of shrinking the content height
	    page_mgr.scale_content(page_id);
	    if (page_id === 'index') {
		map_mgr.resize();
	    }
	} );
	$( document ).on( "pagecontainerchangefailed", function( event, ui ) {
	    console.log(event);
	    console.log(ui);
	} );
	if (device_id_mgr.phonegap) {
	    // deal with the iOS status bar
	    StatusBar.overlaysWebView (false);
	    StatusBar.backgroundColorByHexString ('#66acd0');
	}
    },
    scale_content: function (page_id) {
	scroll(0, 0);
	console.log ("screenHeight:"+$.mobile.getScreenHeight());
	console.log ("ui-header:"+$("#"+page_id+" .ui-header").outerHeight());
	console.log ("ui-footer:"+$("#"+page_id+" .ui-footer").outerHeight());
	console.log ("ui-content outerHeight:"+$("#"+page_id+" .ui-content").outerHeight());
	console.log ("ui-content height:"+$("#"+page_id+" .ui-content").height());
	var content_height =
	    $.mobile.getScreenHeight() -
	    $("#"+page_id+" .ui-header").outerHeight() -
	    $("#"+page_id+" .ui-footer").outerHeight() -
	    $("#"+page_id+" .ui-content").outerHeight() +
	    $("#"+page_id+" .ui-content").height();
	$(".ui-content").height(content_height);
	console.log (content_height);
	map_mgr.resize();
    },
    switch_page: function (page_id, info_id) {
	// clear out old errors
	if (info_id) {
	    $('#'+info_id).empty();
	}

	if (page_id !== 'index') {
	    // clear out index page errors when you move off the index page
	    $('#geo_info').empty();
	}
	$(":mobile-pagecontainer").pagecontainer("change", '#'+page_id,
						 {transition: 'slide',
						  changeHash: false});
	return;
    },
    get_active_page: function () {
	return ($(":mobile-pagecontainer").pagecontainer("getActivePage").attr('id'));
    },
}

var my_pos = {
    // control the initial pan/zoom
    current_position: null,
    marker: null,
    user_action: false,
    set_user_action: function () {
	my_pos.user_action = true;
    },
    update_position: function (position_from_server) {
	if (! device_id_mgr.phonegap || ! position_from_server)
	    return;
	my_pos.current_position = position_from_server;
	my_pos.create (my_pos.current_position);
    },
    create: function (position) {
	if (my_pos.marker)
	    return;
	if (! position)
	    return;
	console.log (Date.now()+": creating green star");
	var image = 'images/current_location.png';

	var marker_parms = { marker_id: 'my_pos',
			     icon: image,
			     position: 	new google.maps.LatLng(position.coords.latitude,
							       position.coords.longitude)};
	var map = $('#map_canvas').gmap('get','map');
	my_pos.marker = $('#map_canvas').gmap('addMarker', marker_parms);
	my_pos.current_position = position;
	return;
    },
    pan_zoom: function () {
	// google maps have a habit of shrinking the display window size
	map_mgr.resize();

	// Don't update the screen if the user has already interacted with it
	if (my_pos.user_action)
	    return;
	
	var bounds = new google.maps.LatLngBounds ();
	// include current position in the bounding box
	if (my_pos.current_position) {
	    // include current position in the bounding box
	    var current_location = new google.maps.LatLng(my_pos.current_position.coords.latitude,
							  my_pos.current_position.coords.longitude);
	    bounds.extend (current_location);
	    console.log (Date.now()+":adding current_location");
	}
	if (! jQuery.isEmptyObject(marker_mgr.markers)) {
	    // create a bounding box with the markers
	    for (var device_id in marker_mgr.markers) {
		var sighting = marker_mgr.markers[device_id].sighting;
		var sighting_location = new google.maps.LatLng(sighting.gps_latitude,
							       sighting.gps_longitude);
		bounds.extend (sighting_location);
		console.log (Date.now()+":adding sighting_location");
	    }
	}

	var map = $('#map_canvas').gmap('get','map');
	if (bounds.isEmpty()) {
	    // no markers and no current location
	    console.log (Date.now()+":fitBounds to us_center");
	    bounds.extend (display_mgr.us_center);
	    map.fitBounds (bounds);
	    map.setZoom(4);
	} else {
	    console.log (Date.now()+":fitBounds to markers/curpos");

	    // we have to do this first or getZoom is wrong
	    map.fitBounds (bounds);

	    // in case we only have one marker, fitBounds zooms to maximum.
	    // Back off to max_zoom
	    var zoom = Math.min(map.getZoom(), 18);
	    map.setZoom(zoom);
	}
	map.setCenter(bounds.getCenter());
	map_mgr.resize();
    },
    reposition: function () {
	run_position_function (function(position) {
	    if (! position)
		return;
	    if (my_pos.marker) {
		my_pos.current_position = position;
		my_pos.marker[0].setPosition(new google.maps.LatLng(position.coords.latitude,
								    position.coords.longitude));
	    } else {
		my_pos.create (position);
	    }
	});
	my_pos.pan_zoom();
    },
};

var device_id_mgr = {
    device_id: null,
    phonegap:  null,
    init: function () {
	// This will not create a device_id for the web app,
	// that happens in the config API call
	// This will create a device_id for the native app
	device_id_mgr.phonegap = true;
	try {
	    device_id_mgr.device_id = device.uuid;
	}
	catch (err) {
	    console.log (err);
	    device_id_mgr.phonegap = false;
	}
	console.log ("device_id="+device_id_mgr.get()+", phonegap="+device_id_mgr.phonegap);
	return;
    },
    get_cookie: function (key) {
	var name = key + "=";
	// get all the cookies (';' delimited)
	var cookies = document.cookie.split(';');
	// look for the cookie starting with '\s*<key>='
	for (var i=0; i<cookies.length; i++) {
	    var cookie = cookies[i];
	    while (cookie.charAt(0)==' ') cookie = cookie.substring(1);
	    if (cookie.indexOf(name) != -1) {
		// found '<key>=' in cookie,
		// return everything after '<key>='
		return cookie.substring(name.length,cookie.length);
	    }
	}
	return;
    },
    get: function () {
	if (! device_id_mgr.device_id) {
	    device_id_mgr.device_id = device_id_mgr.get_cookie ('device_id');
	    // console.log (device_id_mgr.device_id);
	}
	return (device_id_mgr.device_id);
    },
};

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
	console.log (err);
	// some messages should only be displayed once
	if (display_mgr.message_displayed) {
	    return;
	}

	var msg;
	if        (err.code === 1) {
	    msg = "Your current location is blocked.";
	} else if (err.code === 2) {
	    msg = "Your current location is not available.";
	} else if (err.code === 3) {
	    return;
	    msg = "Getting your current location timed out.  We'll keep trying.";
	    // store the div id for this message so we can hide it when the position becomes available
	    display_mgr.timeout_warning_md5 = md5(msg);
	} else {
	    msg = "There was an unknown error getting your current location.";
	}
	if (err.code && msg) {
	    var client_type = get_client_type ();
	    if (device_id_mgr.phonegap) {
		msg = "It looks like you don't have location enabled."
		if (client_type == 'android') {
		    msg += "<br>Fix this in <i>Settings -> Location</i>";
		} else if (client_type == 'ios') {
		    msg += "<br>Fix this in <i>Settings -> Privacy -> Location Services</i>";
		}
	    }
	}
	display_mgr.geo_down = true;
	display_mgr.message_displayed = true;
	display_mgr.last_msg = msg;
	display_message (msg, 'message_warning', 'geo_info');
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
	    display_message ('Your GPS is now available','message_info', 'geo_info');
	}
    }
}

var marker_mgr = {
    // markers = {device_id_1: {sighting: sighting_1, marker: marker_1, label: label_1}, 
    //            device_id_2: {sighting: sighting_2, marker: marker_2, label: label_2}, ...
    //           }
    markers: {},
    selected_sighting: null,
    create_time_elem_str: function (num, unit) {
	if (num == 0) {    
	    return '';
	}
	var str = num + ' ' + unit;
	if (num > 1) {
	    str += 's';
	}
	return (str);
    },
    create_elapsed_str: function (sighting) {
	var elapsed_sec = Math.round ((Date.now() - Date.parse(sighting.sighting_time)) / 1000);
	var elapsed_str;
	if (elapsed_sec < 60) {
	    elapsed_str = elapsed_sec + ' secs';
	} else {
	    var elapsed_min = Math.round (elapsed_sec / 60);
	    if (elapsed_min < 60) {
		elapsed_str = marker_mgr.create_time_elem_str (elapsed_min, 'min');
	    } else {
		var elapsed_hr = Math.round (elapsed_min / 60);
		elapsed_min = elapsed_min % 60;
		if (elapsed_hr < 24) {
		    elapsed_str = marker_mgr.create_time_elem_str (elapsed_hr, 'hr');
		    elapsed_str += ' ';
		    elapsed_str += marker_mgr.create_time_elem_str (elapsed_min, 'min');
		} else {
		    var elapsed_day = Math.round (elapsed_hr / 24);
		    elapsed_hr = elapsed_hr % 24;
		    elapsed_str = marker_mgr.create_time_elem_str (elapsed_day, 'day');
		    elapsed_str += ' ';
		    elapsed_str += marker_mgr.create_time_elem_str (elapsed_hr, 'hr');
		}
	    }
	}
	elapsed_str = '('+elapsed_str+' ago)';
	return (elapsed_str);
    },
    create_label_text: function (sighting) {
	var elapsed_str = marker_mgr.create_elapsed_str (sighting);
	var elapsed_div = '<div class="elapsed_str marker_label">' + elapsed_str + '</div>';
	var name_div = '<div>' + sighting.name + '</div>';
	var div_id = "marker_label_"+sighting.device_id;
	var label_text = '<span id="'+ div_id + '" class="marker_label_text">' +
	    name_div + elapsed_div + '</span>';
	return (label_text);
    },
    update_marker_view: function (marker_info) {
	var sighting = marker_info.sighting;
	var sighting_location = new google.maps.LatLng(sighting.gps_latitude,
						       sighting.gps_longitude);
	var label_text = marker_mgr.create_label_text (sighting);
	$('#map_canvas').gmap('find', 'markers',
			      { 'property': 'device_id', 'value': sighting.device_id },
			      function(marker, found) {
				  if (found) {
				      marker.labelContent = label_text;
				      marker.setPosition(sighting_location);
				  }
			      });
	return;
    },
    latlng_to_point: function (latLng, map) {
	var topRight = map.getProjection().fromLatLngToPoint(map.getBounds().getNorthEast());
	var bottomLeft = map.getProjection().fromLatLngToPoint(map.getBounds().getSouthWest());
	var scale = Math.pow(2, map.getZoom());
	var worldPoint = map.getProjection().fromLatLngToPoint(latLng);
	var point = new google.maps.Point((worldPoint.x - bottomLeft.x) * scale, (worldPoint.y - topRight.y) * scale);
	return (point);
    },
    marker_menu: function (e, sighting) {
	// keep the current sighting in the marker
	marker_mgr.selected_sighting = sighting;

	// reposition the menu so it is over the marker that was clicked
	var map = $('#map_canvas').gmap('get','map');
	var point = marker_mgr.latlng_to_point (e.latLng, map);
	$("#marker_menu").css( {position:"absolute", top:point.y, left:point.x-120} );

	// The menu item to share your location with the marker
	// We only put up this menu item if the server has account info
	// for the currently selected marker
	if (marker_mgr.selected_sighting.have_email == 1 ||
	    marker_mgr.selected_sighting.have_mobile == 1) {
	    $('#share_location_menu_item').show();
	} else {
	    $('#share_location_menu_item').hide();
	}

	if (marker_mgr.selected_sighting.have_email == 1) {
	    $('#send_email_menu_item').show();
	} else {
	    $('#send_email_menu_item').hide();
	}

	if (marker_mgr.selected_sighting.have_mobile == 1) {
	    $('#send_mobile_menu_item').show();
	} else {
	    $('#send_mobile_menu_item').hide();
	}

	// the name can appear in multiple menu items
	$('.menu_account_name').text(marker_mgr.selected_sighting.name);

	if (marker_mgr.selected_sighting.expire_time) {
	    var expire_time = format_time(marker_mgr.selected_sighting.expire_time);
	    $('#share_location_expire_time').html('Expires:<br>'+expire_time);
	    $('#share_location_expire_time_div').show();
	} else {
	    $('#share_location_expire_time_div').hide();
	}

	// ugly hack
	// some rogue event is causing the menu to be closed right away
	// wait .5 sec for that event to clear
	setTimeout (function() {$('#marker_menu .js ul').slideToggle(200)}, 500);
	e.stop();
	return (false);
    },
    send_to_form: function (type) {
	$('#send_to_name').text(marker_mgr.selected_sighting.name);
	$('#send_to_type').text(type);
	$("input[type='hidden'][name='device_id']").val(marker_mgr.selected_sighting.device_id);
	$("input[type='hidden'][name='send_to_type']").val(type);
	$('#send_to_form_info').empty();
	page_mgr.switch_page ('send_to_page');
	return;
    },
    process_send_to_form: function (type) {
	$('#send_to_form_spinner').show();
	form_request ($('#send_to_form'), null, marker_mgr.send_to_callback, geo_ajax_fail_callback);
    },
    send_to_callback: function (data, textStatus, jqXHR) {
	form_request_callback (data, 'send_to_form_spinner', 'send_to_form_info');
    },
    popup_share_location: function () {
	// We got here from the marker menu
	// Send a share to the device_id associated with the marker
	// This will become the share_device_id
	// 
	$('#share_via').hide();
	$('#share_with').show();
	$('#share_account_name').text(marker_mgr.selected_sighting.name);
	$("input[type='hidden'][name='share_device_id']").val(marker_mgr.selected_sighting.device_id);
	page_mgr.switch_page ('share_location_page', 'share_location_form_info');
	return;
    },
    create_marker: function (sighting) {
	var label_text = marker_mgr.create_label_text (sighting);
	var marker = $('#map_canvas').gmap('addMarker', {
	    'device_id':    sighting.device_id,
	    'position':     new google.maps.LatLng(sighting.gps_latitude,sighting.gps_longitude),
	    'marker':       MarkerWithLabel,
	    'icon':         'images/pin_wings.png',
	    'labelAnchor':  new google.maps.Point(60, 0),
	    'labelContent': label_text}).click(function(e) {marker_mgr.marker_menu(e, sighting)});
	console.log (Date.now()+":creating marker "+label_text);
	return ({marker: marker});
    },
    update_markers: function (data, textStatus, jqXHR) {
	if (! data)
	    return;

	// In addition to the markers, the server sends us our position
	// For native (phonegap) apps, the background GPS kills the webview GPS
	// so the server has to send us our position.  Go figure.
	my_pos.update_position (data.current_position);

	var sightings = data.sightings;
	if (! sightings)
	    return;

	// update markers with whatever sightings are received (position change)
	for (var i=0, len=sightings.length; i<len; i++) {
	    var sighting = sightings[i];
	    if (! marker_mgr.markers[sighting.device_id]) {
		marker_mgr.markers[sighting.device_id] = marker_mgr.create_marker (sighting);
	    }
	    // hold the most recent sighting to keep this marker's label up to date
	    marker_mgr.markers[sighting.device_id].sighting = sighting;
	}

	// update the views of all the markers
	// so we update the elapsed time of markers,
	// even where the position has not changed
	for (var device_id in marker_mgr.markers) {
	    marker_mgr.update_marker_view (marker_mgr.markers[device_id]);
	}
	my_pos.pan_zoom();
	marker_mgr.overlap_detection();
    },
    overlaps: function (box_1, box_2) {
	if (! box_1 || ! box_1)
	    return (false);
	var x_overlap =
	    (box_1.x <= box_2.x && box_2.x <= box_1.x+box_1.width) ||
	    (box_2.x <= box_1.x && box_1.x <= box_2.x+box_2.width);
	var y_overlap =
	    (box_1.y <= box_2.y && box_2.y <= box_1.y+box_1.height) ||
	    (box_2.y <= box_1.y && box_1.y <= box_2.y+box_2.height);
	return (x_overlap && y_overlap);
    },
    overlap_detection: function () {
	// if the labels overlap, hide the elapsed time
	var device_ids = [];
	for (var device_id in marker_mgr.markers) {
	    device_ids.push (device_id);
	    // get the parent of our label div
	    var marker_label_id = 'marker_label_'+device_id;
	    var marker_label = $('#'+marker_label_id).parent();
	    if (marker_label.height()) {
		marker_mgr.markers[device_id].bound_box =
		    { 'x'       : marker_label.css('left').replace(/px$/,"") - 0,
		      'y'       : marker_label.css('top').replace(/px$/,"") - 0,
		      'height'  : marker_label.height(),
		      'width'   : marker_label.width(),
		      'overlap' : false,
		    };
	    }
	}

	// compute the pairwise permutations of device ids and check for overlap
	for (var i=0; i<device_ids.length-1; i++) {
	    for (var j=i+1; j<device_ids.length; j++) {
		var box_1 = marker_mgr.markers[device_ids[i]].bound_box;
		var box_2 = marker_mgr.markers[device_ids[j]].bound_box;
		if (marker_mgr.overlaps (box_1, box_2)) {
		    box_1.overlap = true;
		    box_2.overlap = true;
		}
	    }
	}

	// we marked any boxes that overlap
	// comb through all the boxes and set their new visibility
	for (var device_id in marker_mgr.markers) {
	    var marker = marker_mgr.markers[device_id];
	    if (marker.bound_box) {
		var marker_label_id = 'marker_label_'+device_id;
		var elapsed_div = $('#'+marker_label_id).find('.elapsed_str');
		if (marker.bound_box.overlap) {
		    elapsed_div.css('visibility', 'hidden');
		} else {
		    elapsed_div.css('visibility', 'visible');
		}
	    }
	}
    },
    show_directions: function () {
	var url = "https://maps.google.com/maps";
	url += "?daddr="+marker_mgr.selected_sighting.gps_latitude;
	url += ","+marker_mgr.selected_sighting.gps_longitude;
	if (my_pos.current_position) {
	    url += "&saddr="+my_pos.current_position.coords.latitude;
	    url += ","+my_pos.current_position.coords.longitude;
	}
	window.open (url, '_system');
    },
};

//
// Web/Native app handshake
//

var device_id_bind = {
    ran_bind: null,
    countdown_web_app_redirect_div_id: null,
    countdown_native_app_redirect_div_id: null,
    check: function (val) {
	// called with the DB result for device_id_bind_complete
	// If we have never run the device_id_bind for this native app,
	// start the handshake
	console.log (val);

	// Two conditions to launch phase_1:
	//   1) phonegap (native app)
	//   2) haven't done this before (this is only done once at app first start)
	// The phonegap test is superfluous
	// We got here in a db callback, so we only get here in the phonegap app
	if (device_id_mgr.phonegap) {
	    if (val == 1) return;

	    device_id_bind.web_app_redirect_interstitial ();
	    return;
	} else {
	    return 1;
	}
    },
    countdown_web_app_redirect: function () {
	var val = $('#countdown_web_app_redirect').html();
	if (val <= 0) {
	    device_id_bind.web_app_redirect();
	    // we don't get back to here
	} else {
	    val -= 1;
	}
	$('#countdown_web_app_redirect').html(val);
	setTimeout(function() {device_id_bind.countdown_web_app_redirect()}, 1000);
    },    
    countdown_native_app_redirect: function () {
	var val = $('#countdown_native_app_redirect').html();
	if (val == 0) {
	    device_id_bind.native_app_redirect();
	    // we don't get back to here
	} else if (val > 0) {
	    val -= 1;
	    $('#countdown_native_app_redirect').html(val);
	    setTimeout(function() {device_id_bind.countdown_native_app_redirect()}, 1000);
	}
    },    
    web_app_redirect_interstitial: function () {
	var msg = "To finish installation, switch to the web app to copy the shares to the native app.";
	msg += "<p><div class='message_button' onclick='device_id_bind.web_app_redirect()'><div class='message_button_text'>Go to web app</div></div>";
	msg += "<p><span>You will be switched automatically in </span><span id='countdown_web_app_redirect' style='font-size:18px'>11</span><script>device_id_bind.countdown_web_app_redirect()</script>";
	device_id_bind.countdown_web_app_redirect_div_id = display_message (msg, 'message_success', 'geo_info');
    },
    web_app_redirect: function () {
	// kick off the handshake by redirecting to the device browser
	// Bet you didn't know you could get out of the native app's webview :-)

	// Get this div off the page
	// We're done with it and we don't want it firing again
	$('#'+device_id_bind.countdown_web_app_redirect_div_id).remove();
	map_mgr.resize();

	// Defensive coding:
	// This is an in-memory version of globals.device_id_bind_complete
	// This prevents the infinite redirectly loop between the native and web apps if the DB call fails
	if (device_id_bind.ran_bind) {
	    // this is not good.
	    // we should not have been called if this already ran
	    // ran_bind is an in-memory safety net
	    // If the persistant storage check failed, the handshake will be re-run the next time the native app starts
	    // But can't fix it here.  The best we can do is prevent an endless redirect loop
	    console.log ("Prevented redirect loop");
	    return
	} else {
	    device_id_bind.ran_bind = 1;
	}

	// redirect to the web app (webview) telling the webview what our device_id is
	var url = "http://" + host() + "/api?method=device_id_bind";
	url += "&native_device_id=" + device_id_mgr.device_id;
	// MAGIC HERE:
	// This is how we get state from the native app to the web app.
	// The _system parm will cause url to be opened in the device browser,
	// not a webview in the app
	// alert ("About to redirect to "+url);
	window.open(url, '_system');
	// While we don't get back to here,
	// we do get back to this JS file
	// The webview will redirect back to a deeplink
	// which will be handled in handleOpenURL
    },
    native_app_redirect: function (message) {
	// make sure this can't fire again
	$('#'+device_id_bind.countdown_native_app_redirect_div_id).remove();

        var native_app_deeplink = "geopeers://";
	if (message) {
	    native_app_deeplink += "?message="+message;
	}
	window.location = native_app_deeplink;
    },
    phase_2: function (url) {
	// this is the 2nd part of a handshake between the native app (running this routine) and
	// the webapp which called the native app via a deeplink (geopeers://api?<parms>)

	console.log (url);

	// Don't do this check.
	// If we got any kind of deeplink, don't redo the handshake
	// var parms = get_parms (url);
	// if (parms['method'] != 'device_id_bind') {
	//   return;
	// }

	// set this so we don't try to do it again (safety net for DB)
	device_id_bind.ran_bind = 1;

	// if we got this far through the handshake, assume we're good and don't do it again
	db.set_global ('device_id_bind_complete', 1);
    },
}

function device_id_bind_webapp (alert_method, message) {
    // this is only sent to the webapp, so we only need to check for .ready
    $(document).ready(function() {
	init_geo.after_ready();
	display_alert_message(alert_method, message);
    });
}

// this is a magic function name for catching a deeplink call
function handleOpenURL(url) {
    // alert ("in handleOpenURL");
    device_id_bind.ran_bind = 1;
    // let the browser catch up
    setTimeout(function() {device_id_bind.phase_2 (url)}, 0);
}


//
// MAP STUFF
//

var map_mgr = {
    create: function(position) {
	// flip the loading image
	$('#gps_spinner').hide();
	$('#index').show();

	if (position) {
	    var initial_position = new google.maps.LatLng(position.coords.latitude,
							  position.coords.longitude);
	    $('#map_canvas').gmap({center: initial_position});
	    console.log (Date.now()+":"+initial_position);
	} else {
	    // We don't know our current position
	    // show the whole US
	    $('#map_canvas').gmap({center: display_mgr.us_center, zoom:8});
	    console.log (Date.now()+":us_center");
	}

	var map = $('#map_canvas').gmap('get','map');
	google.maps.event.addListener(map, 'bounds_changed', marker_mgr.overlap_detection);
	google.maps.event.addListener(map, 'dragend', my_pos.set_user_action);

	console.log ("map_mgr.create");
	// adjust for markers (if we got them by now)
	my_pos.pan_zoom();
    },
    resize: function() {
	if (page_mgr.get_active_page() === 'index') {
	    var map = $('#map_canvas').gmap('get','map');
	    google.maps.event.trigger(map, 'resize');
	}
    },
}

//
// SEND_POSITION
//

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

//
// My Contacts
//

var my_contacts = {
    populate_dropdown: function(id, optionList) {
	var dropdown = $('#'+id);
	dropdown.empty();
	$.each(optionList, function (i, el) {
	    dropdown.append("<option>" + el.value + "</option>");
	});
	dropdown.selectmenu();
	dropdown.selectmenu('refresh', true);
	dropdown.show();
    },
    callback: function(contact) {
	console.log (contact);
	setTimeout(function() {
	    // for mobile/email
	    // there are two fields
	    //   my_contacts_[mobile|email] - a single display box
	    //   my_contacts_[mobile|email]_dropdown - multi-select dropdown
	    var mobile;
	    $('#my_contacts_mobile').empty();
	    $('#my_contacts_mobile_dropdown').empty();
	    if (contact && contact.phoneNumbers ) {
		if (contact.phoneNumbers.length == 1) {
		    mobile = contact.phoneNumbers[0].value;
		    $('#my_contacts_mobile').html(mobile);
		    $('input:input[name=my_contacts_mobile]').val(mobile);
		} else {
		    my_contacts.populate_dropdown ('my_contacts_mobile_dropdown', contact.phoneNumbers);
		    $('#my_contacts_mobile_dropdown_div').css('display', 'inline-block');
		}
	    } else {
		$('#my_contacts_mobile').html("<i>None</i>");
		$('#my_contacts_mobile_dropdown_div').hide();
	    }

	    var email;
	    $('#my_contacts_email').empty();
	    $('#my_contacts_email_dropdown').empty();
	    if (contact && contact.emails) {
		if (contact.emails.length == 1) {
		    email = contact.emails[0].value;
		    $('#my_contacts_email').html(email);
		    $('input:input[name=my_contacts_email]').val(email);
		} else {
		    my_contacts.populate_dropdown ('my_contacts_email_dropdown', contact.emails);
		    $('#my_contacts_email_dropdown_div').css('display', 'inline-block');
		}
	    } else {
		$('#my_contacts_email').html("<i>None</i>");
		$('#my_contacts_email_dropdown_div').hide();
	    }

	    // manage the UI elements on the popup
	    if (contact && (contact.phoneNumbers || contact.emails)) {
		// we got something back
		// activate the dropdowns (if any)
		$('#share_to_my_contacts').trigger("change");
		$('#share_to_my_contacts').show();

		// turn off the manual inputs
		$('#share_to_mobile').hide();
		$('#share_to_email').hide();
		$('#share_with').hide();
	    }
	}, 500);
    },
    select_contact: function() {
	navigator.contacts.pickContact(function(contact){
	    my_contacts.callback(contact);
	},function(err){
	    console.log('Error: ' + err);
	});
    }
}

//
// SHARE_LOCATION
//

var share_location = {
    clear_elements: function () {
	$('#share_to_my_contacts').hide();
	$('input[name=my_contacts_email]').val('');
	$('#my_contacts_email_dropdown').empty();
	$('input[name=my_contacts_mobile]').val('');
	$('#my_contacts_mobile_dropdown').empty();
	$('input[name=share_via]').val('');
	$('input[name=share_to]').val('');
	$('input[name=share_device_id]').val('');
	$('.share_to_group').val('');
    },
    clear_page: function () {
	// start by showing the share_location form 
	$('#share_via').show();
	share_location.set_share_to('mobile');
	$('#share_to_mobile').show();
	$('#share_to_email').hide();
	$('#share_with').hide();
	share_location.clear_elements();
	$('input[name=share_message]').val('');

	console.log (registration.reg_info ? registration.reg_info.account : "No reg_info");
	if (registration.reg_info &&
	    registration.reg_info.account &&
	    ! registration.reg_info.account.name) {
	    $('#account_name_box').show();
	} else {
	    $('#account_name_box').hide();
	}
    },
    set_share_to: function (display_type) {
	share_location.clear_elements();
	$.each(['email', 'mobile', 'my_contacts'], function (i, type) {
	    $('#share_via_'+type).checkboxradio();
	    if (display_type === type) {
		$('#share_to_'+type).show();
		$('#share_via_'+type).prop('checked',true).checkboxradio('refresh');
	    } else {
		$('#share_to_'+type).hide();
		$('#share_via_'+type).prop('checked',false).checkboxradio('refresh');
	    }
	});
	if (display_type === 'my_contacts') {
	    my_contacts.select_contact();
	}
    },
    main_page: function () {
	var allow_webapp_shares = false;	// used for testing
	if (! device_id_mgr.phonegap && ! allow_webapp_shares) {
	    download.download_app();
	} else {
            // configure page in case it was used previously
	    share_location.clear_page();
	    page_mgr.switch_page ('share_location_page', 'share_location_form_info');
	}
	return;
    },
    callback:  function (data, textStatus, jqXHR) {
	form_request_callback (data, 'share_location_form_spinner', 'share_location_form_info');

	// in case the name was updated, update registration.reg_info
	registration.init();
	return;
    },
    submit_form: function () {
	// location can be shared either by:
	//   1) share_via (email | mobile) / share_to (<addr>)
	//   2) share_device_id - get location from seer_device.account

	// GEOP-48 For now, the input check will happen at the server
	var share_device_id = $('input:input[name=share_device_id]');
	if (0 && share_device_id.length == 0) {
	    var share_via = $("#share_via").val();
	    var share_to = $("#share_to").val();

	    if (share_to.length == 0) {
		display_message ("Please supply the address to send your share to",
				 'message_error', 'share_location_form_info');
		return;
	    }
	    if (share_via == 'email' && ! share_to.match(/.+@.+/)) {
		display_message ("Email should be in the form 'fred@company.com'",
				 'message_error' , 'share_location_form_info');
		return;
	    }
	    share_to.replace(/[\s\-\(\)]/, null);
	    console.log (share_to);
	    if (share_via == 'mobile' && ! share_to.match(/^\d{10}$/)) {
		display_message ("The phone number (share to) must be 10 digits",
				 'message_error', 'share_location_form_info');
		return;
	    }
	}
	$('#share_location_form_spinner').show();
	var tz = jstz.determine();
	// clear out old error messages
	$('#share_location_form_info').empty();
	form_request ($('#share_location_form'), {tz: tz.name()},
		      share_location.callback, geo_ajax_fail_callback);
    }
}

//
// SEND_SUPPORT
//

function send_support_callback (data, textStatus, jqXHR) {
    form_request_callback (data, 'support_form_spinner', 'support_form_info');
}

function send_support () {
    var support_fields = ['problem', 'reproduction', 'feature', 'cool_use'];
    var typed_something;
    for (var i=0; i<support_fields.length; i++) {
	var val = $('#support_form_'+support_fields[i]).val();
	if (val) {
	    typed_something = 1;
	    break;
	}
    }
    if (typeof (typed_something) === 'undefined') {
	display_message ("Please type something in at least one box",
			 'message_error', 'support_form_info');
	return;
    }
    $('#support_form_spinner').show();
    form_request ($('#support_form'), null, send_support_callback, geo_ajax_fail_callback);
}

function display_support () {
    var version = $('#geopeers_config').attr('version');
    $('#support_version').text(version);
    var build_id = $('#geopeers_config').attr('build_id');
    $('#build_id').text(build_id);
    $("input[type='hidden'][name='support_version']").val(build_id);
    $('#support_page').find("input[type=text], textarea").val("");
    $('#support_form_info').empty();
    page_mgr.switch_page ('support_page', 'support_form_info');
    return;
}

//
// CONFIG
//

function config_callback (data, textStatus, jqXHR) {
    if (! data) {
	return;
    }
    if (data.js) {
        console.log (data.js);
        eval (data.js);
    }

    if (data.update) {
	page_mgr.switch_page ('update_app_page', 'update_app_form_info');
    }

    // The server is telling us if there is an account name for this device
    // If not, we want to let the device user supply a name when they send a share
    if (! data.account_name) {
	console.log (data);
	$('#account_name_box').show();
    }

    // things that need device_id to be configured at the server
    if (device_id_mgr.phonegap) {
	db.get_global ('device_id_bind_complete', device_id_bind.check);
	// if we didn't get redirected, we'll still be here after 1000 msec
	setTimeout(function() {
	    background_gps.init ();

	    // sets registration.status
	    registration.init();
	    start_heartbeat();
	}, 1000);
    } else {
	// sets registration.status
	registration.init();
	start_heartbeat();
    }
    return;
}

function send_config () {
    // Timing Hack: launch this here so it's done by the time the config response gets back
    if (device_id_mgr.phonegap) {
	db.init();
    }

    var device_id = device_id_mgr.get();
    var version = $('#geopeers_config').attr('build_id');
    var request_parms = { method: 'config',
			  device_id: device_id,
			  version: version,
    };
    ajax_request (request_parms, config_callback, geo_ajax_fail_callback);

    return;
}

//
// GET_POSITIONS
//

function get_positions () {
    var device_id = device_id_mgr.get();
    if (! device_id)
	return
    var request_parms = { method: 'get_positions',
			  device_id: device_id};
    ajax_request (request_parms, marker_mgr.update_markers, geo_ajax_fail_callback);
    return;
}


//
// GET_SHARES
//

function format_time (time) {
    // JS version of same routine in geo.rb on server

    // date will be in the browser's TZ
    var date = new Date(time);
    var now = new Date();

    var date_format_str, time_format_str;
    if (date.getFullYear() !== now.getFullYear()) {
	date_format_str = "M d, yy";
	time_format_str = " 'at' h:mm tt";
    } else if (date.getMonth() !== now.getMonth()) {
	date_format_str = "M d";
	time_format_str = " 'at' h:mm tt";
    } else if (date.getDate() !== now.getDate()) {
	date_format_str = "M d";
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
    time_str += ' ' + time_zone_str;
    return (time_str);
}

function manage_shares_callback (data, textStatus, jqXHR) {
    // first time thru flag
    var have_expired_shares = false;

    // clear the old contents and reset the display
    $('.share_row').remove();
    $('#manage_msg').hide();
    $('#empty_msg').empty();
    $('#data_table').empty();
    $('#manage_form_spinner').hide();

    if (! data || ! data.shares || data.shares.length == 0) {
	var client_type = get_client_type();
	if (is_phonegap()) {
	    $('#empty_msg').html("You haven't shared your location yet");
	} else {
	    $('#empty_msg').html("You need the native app to share your location");
	}
	$('#empty_msg').show();
	return;
    }

    for (var i=0,len=data.shares.length; i<len; i++){
	// add a row to the table body for each share
	var share = data.shares[i];

	var redeem_name = share.redeem_name ? share.redeem_name : '<Unopened>';
	var expires = share.expire_time ? format_time(share.expire_time) : 'Never';
	var expire_time = new Date(share.expire_time);

	var expired;
	if (share.expire_time && (expire_time.getTime() < Date.now())) {
	    expired = true;
	    have_expired_shares = true;
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

	var row = $('<tr></tr>').addClass('share_row');
	var status_div = $('<div style="font-size:24px"></div>');
	if (expired) {
	    row.addClass ('share_expired');
	    status_div.text('Expired');
	} else {
	    var switch_on_div = $('<label></label>')
		.attr('class', 'cb-enable')
		.append($('<span></span>').text('On'));
	    var switch_off_div = $('<label></label>')
		.attr('class', 'cb-disable')
		.append($('<span></span>').text('Off'));
	    if (share.active) {
		switch_on_div.addClass('selected');
	    } else {
		switch_off_div.addClass('selected');
	    }
	    var onclick_cmd = "share_active_toggle("+share.share_id+")";
	    status_div = $('<div></div>')
		.attr('onclick', onclick_cmd)
		.attr('class', 'switch')
		.append(switch_on_div)
		.append(switch_off_div)
		.append($('<input></input>').attr('type','hidden').attr('name','checkbox'));
	}
	row.append($('<td></td>').html($('<div></div>').text(share_to).addClass('share_text'))
		   .append($('<div></div>').css('margin-top','3px').text('Used: '+redeemed).addClass('share_text'))
		   .append($('<div></div>').css('margin-top','3px').text('Expires: '+expires).addClass('share_text')));
	row.append($('<td></td>').html(status_div));
        row.append($('<td style="display:none"></td>').text(share.redeem_time));
	row.append($('<td style="display:none"></td>').text(share.expire_time));
	$('#manage_info').append(row);
    }

    // TODO
    // turned off until GEOP-40 is fixed
    if (0 && is_orientation ('portrait')) {
	// this message will be cleared when the device is oriented in landscape
	// This is handled in an orientationchange event listener set in init_geo.after_ready
	var orientation_msg = "Viewed best in landscape mode";
	$('#manage_msg').text(orientation_msg);
	$('#manage_msg').show();
    }

    if ($('#manage_table').dataTable.isDataTable()) {
	$('#manage_table').dataTable.draw();
    } else {
	$('#manage_table').dataTable( {
	    retrieve:     true,
	    searching:    false,
	    lengthChange: false,
	    paging:       false,
	    scrollX:      true,
	    order:        [ [ 3, 'desc' ], [ 2, 'desc' ] ],
	} );
    }

    // only show the checkbox UI control if there are expired shares
    if (have_expired_shares) {
	$('#show_hide_expire').show();
    } else {
	$('#show_hide_expire').hide();
    }

    if ($('#show_hide_expire_checkbox').prop('checked')) {
	$('.share_expired').hide();
    } else {
	$('.share_expired').show();
    }
    $('#data_table').show();
}

function manage_shares () {
    var device_id = device_id_mgr.get();
    if (! device_id)
	return;
    var request_parms = { method: 'get_shares',
			  device_id: device_id,
			};
    $('#manage_form_spinner').show();
    page_mgr.switch_page ('share_management_page');
    ajax_request (request_parms, manage_shares_callback, geo_ajax_fail_callback);
    return;
}

function share_active_toggle(share_id) {
    var device_id = device_id_mgr.get();
    if (! device_id)
	return
    var request_parms = { method: 'share_active_toggle',
			  device_id: device_id,
			  share_id:  share_id,
	};
    $('#manage_form_spinner').show();
    ajax_request (request_parms, manage_shares_callback, geo_ajax_fail_callback);
    return;
}

//
// REGISTRATION
//

function validate_registration_form () {
    var name = $('#registration_form #name').val();
    var email = $('#registration_form #email').val();
    var mobile = $('#registration_form #mobile').val();

    mobile = mobile.replace(/[\s\-\(\)]/g, '');
    if (mobile.length > 0 && ! mobile.match(/^\d{10}$/)) {
	display_message ("The mobile number must be 10 digits",
			 'message_error', 'registration_form_info');
	return;
    }

    if (email.length > 0 && ! email.match(/.+@.+/)) {
	display_message ("Email should be in the form 'fred@company.com'",
			 'message_error', 'registration_form_info');
	return;
    }

    return true;
}

function update_registration_info () {
    if (registration.reg_info && registration.reg_info.account) {
	$('#registration_form #name').val(registration.reg_info.account.name);
	$('#registration_form #email').val(registration.reg_info.account.email);
	$('#registration_form #mobile').val(registration.reg_info.account.mobile);
	registration.reg_info.account.name ? $('#account_name_box').hide() : $('#account_name_box').show();
    }
    return;
}

function display_registration () {
    update_registration_info();
    $('#registration_form_info').empty();
    page_mgr.switch_page ('registration_page', 'registration_form_info');
    return;
}

var registration = {
    // registration.init() launches request to get registration status
    // manages the callback and the status variable

    // status isn't used anymore
    status : null,

    reg_info : null,
    init: function () {
	if (registration.status == 'REGISTERED' || registration.status == 'CHECKING')
	    return;
	var device_id = device_id_mgr.get();
	if (device_id) {
	    var request_parms = { method: 'get_registration',
				  device_id: device_id};
	    ajax_request (request_parms, registration.get_callback, geo_ajax_fail_callback);
	    // while the request/response is in the air, we're in an indeterminant state
	    // Anyone who cares about the registration status should assume that the popup 
	    // has been filled out and is in the air.
	    // So don't pop it up again
	    registration.status = 'CHECKING';
	}
    },
    get_callback: function (data, textStatus, jqXHR) {
	console.log (data);
	if (data) {
	    registration.status = 'REGISTERED';
	    registration.reg_info = data;
	    update_registration_info();

	    // initializations that require registration
	    init_geo.update_main_menu();
	} else {
	    registration.status = null;
	}
    },
    send: function () {
	$('#registration_form_info').empty();
	if (! validate_registration_form()) {
	    return;
	}
	$('#registration_form_spinner').show();
	form_request ($('#registration_form'), null, registration.send_callback, geo_ajax_fail_callback);
    },
    send_callback: function (data, textStatus, jqXHR) {
	$('#registration_form_spinner').hide();
	if (data) {
	    registration.status = 'REGISTERED';
	    display_message (data.message, 'message_success', 'registration_form_info');
	} else {
	    display_message ('No data', 'message_error', 'registration_form_info');
	}
	// update reg_info
	registration.init();
	return;
    },
}

var download = {
    download_urls: { ios:     'https://prod.geopeers.com/bin/ios/index.html',
		     android: 'market://search?q=pname:com.geopeers.app',
		     // android: 'https://prod.geopeers.com/bin/android/index.html',
		     // web:     'https://www.geopeers.com',
    },
    download_url: function () {
	var client_type = get_client_type ();
	console.log (client_type);
	var download_url = download.download_urls[client_type];
	return (download_url);
    },
    download_redirect: function () {
	window.location = download.download_url();
    },
    download_app: function () {
	// called from the web app or URL parm (download_app=1)
	if (getParameterByName('download_app')) {
	    // URL parm from server, go straight to redirect
	    download.download_redirect();
	} else {
	    // user pressed pin or Share Location in web app
	    // but sharing location doesn't work in the web app (no GPS in web workers)
	    // so we have to send them somewhere towards the native app
	    //
	    // 3 possibilities:
	    //   1) native app already installed
	    //   2) native app not installed, but available
	    //   3) native app not installed, not available
	    if (have_native_app()) {
		// Offer to switch to native app
		page_mgr.switch_page ('native_app_switch_page');
	    } else {
		if (download.download_url()) {
		    // don't start the download without warning them in a popup
		    page_mgr.switch_page ('download_app_page', 'download_app_form_info');
		} else {
		    // we don't have a native app for this device, offer to send a link
		    $('#native_app_not_available').show();
		    page_mgr.switch_page ('download_link_page', 'download_link_form_info');
		}
	    }
	}
    },
    send_link: function () {
	$('#download_link_form_spinner').show();
	form_request ($('#download_link_form'), null, download.send_link_callback);
    },
    send_link_callback: function (data, textStatus, jqXHR) {
	form_request_callback (data, 'download_link_form_spinner', 'download_link_form_info');
    },
};

function download_app_wrapper () {
    download.download_app();
}

function download_link_wrapper () {
    $('#native_app_not_available').hide();
    page_mgr.switch_page ('download_link_page', 'download_link_form_info');
}

function download_redirect_wrapper () {
    download.download_redirect();
}

function web_app_redirect_wrapper () {
    device_id_bind.web_app_redirect();   
}

function native_app_redirect_wrapper () {
    device_id_bind.native_app_redirect();
}

//
// Init and startup
//

function start_heartbeat () {
    // start one beat immediately
    heartbeat();

    // normally, heartbeats are every 60 sec
    // but queue one heartbeat after 10 sec to try to get past all the initialization foo
    setTimeout(heartbeat, 10 * 1000);
    return;
}

function heartbeat () {
    // things that should happen periodically
    var period_secs = 60;

    // refresh the sightings for our shares
    get_positions();

    // keep the green star in the right spot
    my_pos.reposition();

    // last ditch to keep the UI clean
    my_pos.pan_zoom();

    // if we get here, schedule the next iteration
    setTimeout(heartbeat, period_secs * 1000);
    return;
}

var init_geo = {
    after_ready: function () {
	// This is called after we are ready
	// for webapp, this is $.ready,
	// for phonegap, this is deviceready

	console.log ("in init");

	// set this globally to clear the orientation warning on the share management popup
	// if the device switches into landscape
	// TODO
	// turn on when GEOP-40 is fixed
	// window.addEventListener('orientationchange', change_orientation);

	run_position_function (function(position) {map_mgr.create(position)});

	device_id_mgr.init ();

	send_config ();

	init_geo.init_switches();

	// There is more initialization, but it happens in the config callback
	// because it relies on the device_id being set

	// There are some things that can be done while we wait for the config API to return

	// server can pass parameters when it redirected to us
	var message_div_id = display_alert_message();

	// This may cause a redirect to the download URL, so do this last
	if (getParameterByName('download_app')) {
	    download.download_app();
	}

	// keep updating bounding box pan/zoom for first pan_zoom_window sec
	// after that, the user has to pan/zoom manually
	var pan_zoom_window = 5;
	for (var i=1; i<pan_zoom_window; i++) {
	    setTimeout(my_pos.pan_zoom, 1000*i);
	}

	// share location page in known state
	share_location.clear_page();

	page_mgr.init();
    },
    init_switches: function () {
	$(".cb-enable").click(function(){
		var parent = $(this).parents('.switch');
		$('.cb-disable',parent).removeClass('selected');
		$(this).addClass('selected');
		$('.checkbox',parent).attr('checked', true);
	    });
	$(".cb-disable").click(function(){
		var parent = $(this).parents('.switch');
		$('.cb-enable',parent).removeClass('selected');
		$(this).addClass('selected');
		$('.checkbox',parent).attr('checked', false);
	    });
    },
    update_main_menu: function () {
	// the default view is for native apps:
	//   Send Link for Native App
	//   Download Native App (hidden)
	//   Switch to Native App (hidden)
	if (! is_phonegap() ) {
	    if (have_native_app()) {
		// Show the deeplink on the main menu to switch to the native app
		$('#native_app_switch').show();
	    }
	    // Show the download link even if we think we have_native_app
	    // If the app was deleted, we won't know about it
	    if (download.download_url()) {
		$('#native_app_download').show();
	    }
	}
    },
};

function start () {
    console.log ('start');
    $(document).ready(function() {
	    if (is_phonegap()) {
		// Wait for device API libraries to load
		document.addEventListener("deviceready", init_geo.after_ready);
	    } else {
		init_geo.after_ready();
	    }
	});
}

