$(function() {
	// Clickable Dropdown
	$('.dropdown_menu > ul').toggleClass('no-js js');
	$('.dropdown_menu .js ul').hide();
	$('#main_menu .js').click(function(e) {
		$('#main_menu .js ul').slideToggle(200);
		e.stopPropagation();
	    });
	$(document).click(function() {
		if ($('.dropdown_menu .js ul').is(':visible')) {
		    $('.dropdown_menu .js ul', this).slideUp();
		}
	    });
    });
