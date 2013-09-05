-- @tag: remove_menustyle_xml
-- @description: Menütyp "XUL/XML" wurde entfernt; also durch v3 ersetzen
-- @depends:
-- @charset: utf-8
UPDATE auth.user_config
SET cfg_value = 'v3'
WHERE ((cfg_key   = 'menustyle')
  AND  (cfg_value = 'xml'));
