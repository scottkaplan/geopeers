$(function() {
	var form, dialog_register,
	    name = $( "#name" ),
	    email = $( "#email" ),
	    allFields = $( [] ).add( name ).add( email ),
	    tips = $( ".validateTips" );
 
	function updateTips( t ) {
	    tips
		.text( t )
		.addClass( "ui-state-highlight" );
	    setTimeout(function() {
		    tips.removeClass( "ui-state-highlight", 1500 );
		}, 500 );
	}
 
	function checkLength( o, n, min, max ) {
	    if ( o.val().length > max || o.val().length < min ) {
		o.addClass( "ui-state-error" );
		updateTips( "Length of " + n + " must be between " +
			    min + " and " + max + "." );
		return false;
	    } else {
		return true;
	    }
	}
 
	function checkRegexp( o, regexp, n ) {
	    if ( !( regexp.test( o.val() ) ) ) {
		o.addClass( "ui-state-error" );
		updateTips( n );
		return false;
	    } else {
		return true;
	    }
	}
 
	function register_device() {
	    var valid = true;
	    allFields.removeClass( "ui-state-error" );
 
	    valid = valid && checkLength( name, "username", 3, 16 );
	    valid = valid && checkLength( email, "email", 6, 80 );
 
	    valid = valid && checkRegexp( name, /^[a-z]([0-9a-z_\s])+$/i, "Username may consist of a-z, 0-9, underscores, spaces and must begin with a letter." );
	    valid = valid && checkRegexp( email, emailRegex, "eg. smith@company.com" );
 
	    if ( valid ) {
		alert (name.val() + ',' + email.val())
		dialog_register.dialog( "close" );
	    }
	    return valid;
	}
 
	dialog_register = $( "#registration-dialog-form" ).dialog({
		autoOpen: false,
		height: 300,
		width: 350,
		modal: true,
		buttons: {
		    "Register": register_device,
		    Cancel: function() {
			dialog_register.dialog( "close" );
		    }
		},
		close: function() {
		    form[ 0 ].reset();
		    allFields.removeClass( "ui-state-error" );
		}
	    });
 
	form = dialog_register.find( "form" ).on( "submit", function( event ) {
		event.preventDefault();
		register_device();
	    });
 
	$( "#bookmark_icon" ).on( "click", function() {
		dialog_register.dialog( "open" );
	    });

	// From http://www.whatwg.org/specs/web-apps/current-work/multipage/states-of-the-type-attribute.html#e-mail-state-%28type=email%29
	var emailRegex = /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/;

  });
