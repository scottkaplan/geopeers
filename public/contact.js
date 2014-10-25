document.addEventListener("deviceready", onDeviceReady, false);
function onDeviceReady() {
}

function got_contact(contact) {
    alert('The following contact has been selected:' + JSON.stringify(contact));
}

function got_contacts(contacts) {
    contacts.every(function(contact, index, array) {
	    alert('Contact:' + JSON.stringify(contact));
	});
}

function de_cameonet() {
    navigator.contacts.pickContact(function(contact){
	    got_contact(contact);
	},function(err){
	    alert('Error: ' + err);
	});
}

function com_badrit() {
    window.plugins.ContactPicker.chooseContact(function(contactInfo) {
	    got_contact(contactInfo);
	});
}

function pick_contact() {
    navigator.contacts.pickContact(function(contact){
	    got_contact(contact);
	},function(err){
	    console.log('Error: ' + err);
	});
}

function onError(contactError) {
    alert (contactError);
}

function find_contact() {
    var options      = new ContactFindOptions();
    options.filter   = "Scott";
    options.multiple = true;
    var fields       = [navigator.contacts.fieldType.displayName,
			navigator.contacts.fieldType.name];
    navigator.contacts.find(fields, got_contacts, onError, options);
}


