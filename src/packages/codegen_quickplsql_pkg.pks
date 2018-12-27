create or replace package codegen_quickplsql_pkg
as

  /*
  
  Purpose:    PL/SQL code generator, inspired by "QuickSQL" markup
  
  Remarks:    
  
  Date        Who  Description
  ----------  ---  -------------------------------------
  31.07.2018  MBR  Created
  
  */

  g_output_mode_htp_buffer       constant varchar2(30) := 'HTP';
  g_output_mode_script           constant varchar2(30) := 'SQL';
  g_output_mode_zip              constant varchar2(30) := 'ZIP';

  -- set global settings
  procedure set_global_settings (p_author_initials in varchar2);

  -- generate code
  procedure generate_code (p_text in varchar2);

  -- download code (as single sql script or zip file with multiple generated files)
  procedure download_code (p_text in varchar2,
  	                       p_output_mode in varchar2 := null);

end codegen_quickplsql_pkg;
/
