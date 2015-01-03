* TODO [2015-01-03 Sat] periga-argv: Option to enable json/yaml for nullable simple scalar (to enable C<--str-json '~'>).
* IDEA [2014-11-01 Sat] ri, periga-argv, pericmd: suppress accepting --foo-json/--foo-yaml even though arg is array etc

  contoh, gw ingin accept file sebagai --file F1 --file F2 saja, gak mau user bisa
  --file-json '["F1","F2"]'. terutama utk array of simple scalar, gw hanya ingin
  itu.
  
  tentu saja kita bisa matikan per_arg_json, per_arg_yaml. mungkin perlu ada
  per-arg optionnya. dan belum ada cara utk specify ini dari pericmd.
