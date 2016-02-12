[%- USE T8 %]
$(function() {
[% IF datefmt %]
  setupPoints('[% MYCONFIG.numberformat %]', '[% 'wrongformat' | $T8 %]');
  setupDateFormat('[% MYCONFIG.dateformat %]', '[% 'Falsches Datumsformat!' | $T8 %]');

  $.datepicker.setDefaults(
    $.extend({}, $.datepicker.regional["[% MYCONFIG.countrycode %]"], {
      dateFormat: "[% datefmt %]",
      showOn: "button",
      showButtonPanel: true,
      changeMonth: true,
      changeYear: true,
      buttonImage: "image/calendar.png",
      buttonImageOnly: true
  }));

  kivi.reinit_widgets();
[% END %]

[% IF ajax_spinner %]
  $(document).ajaxSend(function() {
    $('#ajax-spinner').show();
  }).ajaxStop(function() {
    $('#ajax-spinner').hide();
  });
[% END %]
});

function fokus() {
[%- IF focus -%]
  $('[% focus %]').focus();
[%- END -%]
}

/**
 * Takes a URL and goes to it using the POST method.
 * @param {string} url  The URL with the GET parameters to go to.
 * @param {boolean=} multipart  Indicates that the data will be sent using the
 *     multipart enctype.
 */
function postURL(url, multipart) {
  var form = document.createElement("FORM");
  form.method = "POST";
  if(multipart) {
    form.enctype = "multipart/form-data";
  }
  form.style.display = "none";
  document.body.appendChild(form);
  form.action = url.replace(/\?(.*)/, function(_, urlArgs) {
    urlArgs.replace(/\+/g, " ").replace(/([^&=]+)=([^&=]*)/g, function(input, key, value) {
      input = document.createElement("INPUT");
      input.type = "hidden";
      input.name = decodeURIComponent(key);
      input.value = decodeURIComponent(value);
      form.appendChild(input);
    });
    return "";
  });
  form.submit();
}

function getYearDDFilterStr() {
  if($.cookie('yearDD') != null && $.cookie('yearDD') != "all") {
    return "&datefrom=01.01."+$.cookie('yearDD')+"&dateto=31.12."+$.cookie('yearDD')+"&transdatefrom=01.01."+$.cookie('yearDD')+"&transdateto=31.12."+$.cookie('yearDD');
  }
  else {
    return "";
  } 
}

function gotoBuchungen() {
  document.location = "gl.pl?action=generate_report&datesort=gldate&category=X&l_gldate=Y&l_transdate=Y&l_reference=Y&l_description=Y&l_debit=Y&l_credit=Y&sort=transdate&sortdir=0"+getYearDDFilterStr();
}

function gotoRechnungen() {
  document.location = "ar.pl?action=Weiter&nextsub=ar_transactions&open=1&closed=1&l_amount=Y&l_invnumber=Y&l_name=Y&l_netamount=Y&l_paid=Y&l_transdate=Y&sort=transdate"+getYearDDFilterStr();
}

// init year preselection dropdown
yearDD();
$('#yearDD').change(function() {
    $.cookie('yearDD', $(this).val(), {
             expires: 365}
             );
    //refresh either buchungen or rechnungen page
    if(window.location.href.indexOf("gl.pl") != -1){gotoBuchungen();}
    if(window.location.href.indexOf("ar.pl") != -1){gotoRechnungen();}
});
