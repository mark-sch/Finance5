// NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE:

// This file is generated automatically by the script
// "scripts/generate_client_js_actions.pl". See the documentation for
// SL/ClientJS.pm for instructions.

namespace("kivi", function(ns) {
ns.display_flash = function(type, message) {
  $('#flash_' + type + '_content').text(message);
  $('#flash_' + type).show();
};

ns.eval_json_result = function(data) {
  if (!data)
    return;

  if (data.error)
    return ns.display_flash('error', data.error);

  $(['info', 'warning', 'error']).each(function(idx, category) {
    $('#flash_' + category).hide();
    $('#flash_' + category + '_content').empty();
  });

  if ((data.js || '') != '')
    eval(data.js);

  if (data.eval_actions)
    $(data.eval_actions).each(function(idx, action) {
      // console.log("ACTION " + action[0] + " ON " + action[1]);

[% actions %]
    });

  // console.log("current_content_type " + $('#current_content_type').val() + ' ID ' + $('#current_content_id').val());
};

});

// Local Variables:
// mode: js
// End:
