create or replace package body codegen_quickplsql_pkg
as

  /*
  
  Purpose:    PL/SQL code generator, inspired by "QuickSQL" markup
  
  Remarks:    
  
  Date        Who  Description
  ----------  ---  -------------------------------------
  31.07.2018  MBR  Created
  04.09.2018  MBR  Set logger default on package level
  
  */

  type t_global_settings is record (
    author_initials    varchar2(3),
    generated_date     date default sysdate
  );

  type t_param is record (
    param_name         varchar2(128),
    param_direction    varchar2(30),
    param_datatype     varchar2(128),
    param_default      varchar2(4000),
    param_raw_text     varchar2(4000)
  );

  type t_param_list is table of t_param index by pls_integer;

  type t_subprogram is record (
    subprogram_type     varchar2(30),
    subprogram_name     varchar2(128),
    subprogram_remarks  varchar2(4000),
    subprogram_params   varchar2(4000),
    subprogram_return   varchar2(4000),
    is_private          boolean,
    is_logger_enabled   boolean,
    crud_table          varchar2(128),
    crud_key            varchar2(128),
    crud_operation      varchar2(30),
    param_list          t_param_list
  );

  type t_subprogram_list is table of t_subprogram index by pls_integer;

  type t_package is record (
    package_name       varchar2(128),
    package_remarks    varchar2(4000),
    subprogram_list    t_subprogram_list,
    is_logger_enabled  boolean,
    crud_table         varchar2(128),
    crud_key           varchar2(128)
  );

  type t_package_list is table of t_package index by pls_integer;

  g_global_settings              t_global_settings;
  g_package_list                 t_package_list;
  g_package_count                pls_integer := 0;
  g_output_mode                  varchar2(30) := g_output_mode_htp_buffer;
  g_output_clob                  clob;
  g_output_zip                   blob;

function get_value (p_str in varchar2,
	                  p_starts_with in varchar2 := null,
	                  p_ends_with in varchar2 := null) return varchar2
as
  l_start_pos   number;
  l_end_pos     number;
  l_returnvalue varchar2(4000);
begin

  if p_str is not null then
  	if p_starts_with is null then
  	  l_start_pos := 1;
  	else
      l_start_pos := instr(p_str, p_starts_with);
  	end if;
  	if l_start_pos > 0 then
  	  l_returnvalue := substr(p_str, l_start_pos + nvl(length (p_starts_with),0));
  	  if p_ends_with is not null then
  	  	l_end_pos := instr(l_returnvalue, p_ends_with);
  	  	if l_end_pos > 0 then
          l_returnvalue := substr(l_returnvalue, 1, l_end_pos - 1);
  	  	end if;
  	  end if;
  	end if;
  end if;

  l_returnvalue := trim (l_returnvalue);

  return l_returnvalue;

end get_value;


procedure output_line (p_line in varchar2)
as
begin
  if g_output_mode = g_output_mode_htp_buffer then
    htp.p (p_line);
  else
    g_output_clob := g_output_clob || p_line || chr(13) || chr(10);
  end if;
end output_line;


procedure output_file (p_file_name in varchar2)
as
  l_file_content blob;
begin

  if g_output_mode = g_output_mode_zip then
    -- take what has been generated so far (in clob), convert to blob, and add to zip file, then reset clob to null
    l_file_content := sql_util_pkg.clob_to_blob (g_output_clob);
    apex_zip.add_file (p_zipped_blob => g_output_zip, p_file_name => p_file_name, p_content => l_file_content);
    g_output_clob := null;
  end if;

  null;

end output_file;


procedure parse_text (p_text in varchar2)
as

  cursor l_line_cursor
  is
  select replace(replace(column_value, chr(10), ''), chr(13), '') as the_line
  from table(apex_string.grep (p_text, p_pattern => '.*' || chr(10)));

  cursor l_param_cursor (p_params in varchar2)
  is
  select trim(column_value) as the_param
  from table(apex_string.split(p_params, p_sep => ','));

  l_param            t_param;
  l_subprogram       t_subprogram;
  l_subprogram_count pls_integer;

begin

  for l_line_rec in l_line_cursor loop
    if l_line_rec.the_line like 'package %' then
      g_package_count := g_package_count + 1;
      l_subprogram_count := 0;
      g_package_list(g_package_count).package_name := get_value (l_line_rec.the_line, 'package ', '--');
      g_package_list(g_package_count).package_remarks := get_value (l_line_rec.the_line, '--', '[');
      g_package_list(g_package_count).is_logger_enabled := instr(l_line_rec.the_line, '[logger]') > 0;
      if instr(l_line_rec.the_line, '[crud-table:') > 0 then
        g_package_list(g_package_count).crud_table := get_value (l_line_rec.the_line, '[crud-table:', ']');
      end if;
      if instr(l_line_rec.the_line, '[crud-key:') > 0 then
        g_package_list(g_package_count).crud_key := get_value (l_line_rec.the_line, '[crud-key:', ']');
      end if;
    elsif l_line_rec.the_line like '  %' then
      l_subprogram_count := l_subprogram_count + 1;
      l_subprogram := null;
      l_subprogram.subprogram_name := get_value (l_line_rec.the_line, null, '(');
      l_subprogram.subprogram_params := get_value (l_line_rec.the_line, '(', ')');

      for l_param_rec in l_param_cursor (l_subprogram.subprogram_params) loop
        l_param := null;
        l_param.param_raw_text := l_param_rec.the_param;
        l_param.param_name := string_util_pkg.get_nth_token (l_param_rec.the_param, 1, ' ');
        l_param.param_direction := string_util_pkg.get_nth_token (l_param_rec.the_param, 2, ' ');
        l_param.param_datatype := string_util_pkg.get_nth_token (l_param_rec.the_param, 3, ' ');
        l_param.param_default := coalesce (get_value (l_param_rec.the_param, 'default '), get_value (l_param_rec.the_param, ':= ') );
        l_subprogram.param_list(l_param_cursor%rowcount) := l_param;
      end loop;

      l_subprogram.subprogram_return := get_value (l_line_rec.the_line, 'return ', '--');
      l_subprogram.subprogram_type := case when l_subprogram.subprogram_return is not null then 'function' else 'procedure' end;
      l_subprogram.subprogram_remarks := get_value (l_line_rec.the_line, '--', '[');
      l_subprogram.is_private := instr(l_line_rec.the_line, '[private]') > 0;
      if g_package_list(g_package_count).is_logger_enabled then
        l_subprogram.is_logger_enabled := true;
      else
        l_subprogram.is_logger_enabled := instr(l_line_rec.the_line, '[logger]') > 0;
      end if;
      l_subprogram.crud_table := coalesce(get_value (l_line_rec.the_line, '[crud-table:', ']'), g_package_list(g_package_count).crud_table);
      l_subprogram.crud_key := coalesce(get_value (l_line_rec.the_line, '[crud-key:', ']'), g_package_list(g_package_count).crud_key);
      l_subprogram.crud_operation := get_value (l_line_rec.the_line, '[crud-', ']');
      g_package_list(g_package_count).subprogram_list(l_subprogram_count) := l_subprogram;
    end if;
  end loop;

end parse_text;


procedure init_gen (p_text in varchar2)
as
begin
  g_global_settings.author_initials := nvl(g_global_settings.author_initials, 'MRX');
  g_package_list.delete;
  g_package_count := 0;
  parse_text (p_text || chr(10) || chr(10));
end init_gen;


procedure finish_gen
as
begin
  if g_output_mode = g_output_mode_zip then
    apex_zip.finish (p_zipped_blob => g_output_zip);
  end if;
end finish_gen;


procedure generate_remarks (p_remarks in varchar2)
as
begin

  output_line ('  /*');
  output_line ('  ');
  output_line ('  Purpose:    ' || p_remarks);
  output_line ('  ');
  output_line ('  Remarks:    ');
  output_line ('  ');
  output_line ('  Date        Who  Description');
  output_line ('  ----------  ---  -------------------------------------');
  output_line ('  ' || to_char(g_global_settings.generated_date, 'dd.mm.yyyy') || '  ' || g_global_settings.author_initials || '  Created');
  output_line ('');
  output_line ('  */');

end generate_remarks;


function format_params (p_params in varchar2,
                        p_lpad_chars in number := 0) return varchar2
as
  l_returnvalue varchar2(32000);
begin

  if g_output_mode = g_output_mode_htp_buffer then
    l_returnvalue := replace(p_params, ',', ',' || chr(10) || lpad(' ', p_lpad_chars));
  else
    l_returnvalue := replace(p_params, ',', ',' || chr(13) || chr(10) || lpad(' ', p_lpad_chars));
  end if;

  return l_returnvalue;

end format_params;


function get_column_name_by_param_name (p_param_name in varchar2) return varchar2
as
  l_returnvalue varchar2(128);
begin

  l_returnvalue := p_param_name;

  if substr(l_returnvalue, 1, 2) = 'p_' then
    l_returnvalue := substr(l_returnvalue, 3);
  end if;

  return l_returnvalue;
    
end get_column_name_by_param_name;


procedure generate_subprogram_headers (p_subprogram_list in t_subprogram_list)
as
begin

  for i in 1 .. p_subprogram_list.count loop
    if not p_subprogram_list(i).is_private then
      if p_subprogram_list(i).subprogram_remarks is not null then
        output_line ('  -- ' || p_subprogram_list(i).subprogram_remarks);
      end if;
      output_line ('  ' ||
        p_subprogram_list(i).subprogram_type || ' ' ||
        p_subprogram_list(i).subprogram_name || ' (' ||
        format_params (p_subprogram_list(i).subprogram_params, p_lpad_chars => length (p_subprogram_list(i).subprogram_type || ' ' || p_subprogram_list(i).subprogram_name) + 3) || ')' ||
        case when p_subprogram_list(i).subprogram_type = 'function' then ' return ' ||
        p_subprogram_list(i).subprogram_return end || ';'
      );
      output_line ('');
    end if;
  end loop;

end generate_subprogram_headers;


procedure generate_subprogram_bodies (p_subprogram_list in t_subprogram_list)
as
  l_crud_key_name        varchar2(128);
  l_crud_key_param_name  varchar2(128);
  l_column_names         varchar2(32000);
  l_param_names          varchar2(32000);
  l_is_function          boolean;
begin

  -- for logger best practices, see https://github.com/OraOpenSource/Logger/blob/master/docs/Best%20Practices.md

  for i in 1 .. p_subprogram_list.count loop

    l_is_function := p_subprogram_list(i).subprogram_type = 'function';

    output_line (p_subprogram_list(i).subprogram_type || ' ' ||
      p_subprogram_list(i).subprogram_name || ' (' ||
      format_params (p_subprogram_list(i).subprogram_params, p_lpad_chars => length (p_subprogram_list(i).subprogram_type || ' ' || p_subprogram_list(i).subprogram_name) + 1) || ')' ||
      case when l_is_function then ' return ' || p_subprogram_list(i).subprogram_return end
    );

    output_line ('as');
    if p_subprogram_list(i).is_logger_enabled then
      output_line ('  l_scope  logger_logs.scope%type := lower($$plsql_unit) || ''.'' || ''' || p_subprogram_list(i).subprogram_name || ''';');
      output_line ('  l_params logger.tab_param;');
    end if;
    if l_is_function then
      output_line ('  l_returnvalue ' || p_subprogram_list(i).subprogram_return || ';');
    end if;    
    output_line ('begin');
    output_line ('');
    generate_remarks (p_subprogram_list(i).subprogram_remarks);
    output_line ('');

    if p_subprogram_list(i).is_logger_enabled then
      for l_param_index in 1 .. p_subprogram_list(i).param_list.count loop
        output_line ('  logger.append_param(l_params, ''' || p_subprogram_list(i).param_list(l_param_index).param_name || ''', ' || p_subprogram_list(i).param_list(l_param_index).param_name || ');');
      end loop;
      output_line ('  logger.log(''START'', l_scope, null, l_params);');
      output_line ('');
    end if;

    if (p_subprogram_list(i).crud_table is not null) and (p_subprogram_list(i).crud_operation is not null) then
      l_crud_key_name := nvl(p_subprogram_list(i).crud_key, p_subprogram_list(i).crud_table || '_id');
      if p_subprogram_list(i).param_list.count > 0 then
        l_crud_key_param_name := p_subprogram_list(i).param_list(1).param_name;
      else
        l_crud_key_param_name := 'p_' || p_subprogram_list(i).crud_table || '_id';
      end if;
      if p_subprogram_list(i).crud_operation = 'create' then
        if p_subprogram_list(i).subprogram_params like 'p_row in%' then
          output_line ('  insert into ' || p_subprogram_list(i).crud_table);
          output_line ('  values p_row');
          output_line ('  returning ' || l_crud_key_name || ' into l_returnvalue;');
        else
          for l_param_index in 1 .. p_subprogram_list(i).param_list.count loop
            l_param_names := l_param_names || p_subprogram_list(i).param_list(l_param_index).param_name || case when l_param_index < p_subprogram_list(i).param_list.count then ', ' end;
            l_column_names := l_column_names || get_column_name_by_param_name(p_subprogram_list(i).param_list(l_param_index).param_name) || case when l_param_index < p_subprogram_list(i).param_list.count then ', ' end;
          end loop;
          output_line ('  insert into ' || p_subprogram_list(i).crud_table || ' (' || l_column_names || ')');
          output_line ('  values (' || l_param_names || ')');
          output_line ('  returning ' || l_crud_key_name || ' into l_returnvalue;');
        end if;
      elsif p_subprogram_list(i).crud_operation = 'read' then
        output_line ('  begin');
        if substr(p_subprogram_list(i).subprogram_return,-5) = '%type' then
          output_line ('    select ' || get_value(p_subprogram_list(i).subprogram_return, '.', '%type'));
        else
          output_line ('    select *');
        end if;
        output_line ('    into l_returnvalue');
        output_line ('    from ' || p_subprogram_list(i).crud_table);
        output_line ('    where ' || l_crud_key_name || ' = ' || l_crud_key_param_name || ';');
        output_line ('  exception');
        output_line ('    when no_data_found then');
        output_line ('      l_returnvalue := null;');
        output_line ('  end;');
      elsif p_subprogram_list(i).crud_operation = 'update' then
        output_line ('  update ' || p_subprogram_list(i).crud_table);
        if p_subprogram_list(i).subprogram_params like '%rowtype' then
          output_line ('  set row = ' || l_crud_key_param_name);
          output_line ('  where ' || l_crud_key_name || ' = ' || l_crud_key_param_name || '.' || l_crud_key_name || ';');
        else
          -- NOTE: start at index 2, because the PK column is assumed to be the first parameter
          for l_param_index in 2 .. p_subprogram_list(i).param_list.count loop
            if l_param_index = 2 then
              output_line ('  set ' || get_column_name_by_param_name(p_subprogram_list(i).param_list(l_param_index).param_name) || ' = ' || p_subprogram_list(i).param_list(l_param_index).param_name || case when l_param_index < p_subprogram_list(i).param_list.count then ', ' end);
            else
              output_line ('    ' || get_column_name_by_param_name(p_subprogram_list(i).param_list(l_param_index).param_name) || ' = ' || p_subprogram_list(i).param_list(l_param_index).param_name || case when l_param_index < p_subprogram_list(i).param_list.count then ', ' end);
            end if;
          end loop;
          output_line ('  where ' || l_crud_key_name || ' = ' || l_crud_key_param_name || ';');
        end if;
      elsif p_subprogram_list(i).crud_operation = 'delete' then
        output_line ('  delete');
        output_line ('  from ' || p_subprogram_list(i).crud_table);
        output_line ('  where ' || l_crud_key_name || ' = ' || l_crud_key_param_name || ';');
      else
        output_line ('  -- unsupported crud operation "' || p_subprogram_list(i).crud_operation || '"');
        output_line ('  null;');
      end if;
    elsif p_subprogram_list(i).subprogram_return like '%rowtype' then
      output_line ('  begin');
      output_line ('    select *');
      output_line ('    into l_returnvalue');
      output_line ('    from ' || replace(p_subprogram_list(i).subprogram_return, '%rowtype', ''));
      output_line ('    where id = ' || 'p_id' || ';');
      output_line ('  exception');
      output_line ('    when no_data_found then');
      output_line ('      l_returnvalue := null;');
      output_line ('  end;');
    else
      output_line ('  -- TODO: add your own magic here...');
      output_line ('  null;');
    end if;
    output_line ('');

    if p_subprogram_list(i).is_logger_enabled then
      output_line ('  logger.log(''END'', l_scope);');
      output_line ('');
    end if;

    if l_is_function then
      output_line ('  return l_returnvalue;');
      output_line ('');
    end if;

    if p_subprogram_list(i).is_logger_enabled then
      output_line ('exception');
      output_line ('  when others then');
      output_line ('    logger.log_error(''Unhandled Exception'', l_scope, null, l_params);');
      output_line ('    raise;');
      output_line ('');
    end if;

    output_line ('end ' || p_subprogram_list(i).subprogram_name || ';');
    output_line ('');
    output_line ('');
  end loop;

end generate_subprogram_bodies;


procedure generate_output
as
begin

  output_line ('-- ');
  output_line ('-- Generated by ' || g_global_settings.author_initials || ' on ' || to_char(sysdate, 'dd.mm.yyyy hh24:mi:ss') || ' using Quick PL/SQL');
  output_line ('-- ');
  output_line ('-- ');
  output_line ('-- Number of generated packages: ' || g_package_list.count);
  output_line ('-- ');
  output_line ('');

  if g_output_mode = g_output_mode_zip then
    output_line ('alter session set plsql_optimize_level = 3;');
    output_line ('set define off;');
    output_line ('');
    output_line ('prompt Installing package specifications...');
    output_line ('');
    for i in 1 .. g_package_count loop
      output_line (chr(64) || g_package_list(i).package_name || '.pks');
    end loop;
    output_line ('');
    output_line ('prompt Installing package bodies...');
    output_line ('');
    for i in 1 .. g_package_count loop
      output_line (chr(64) || g_package_list(i).package_name || '.pkb');
    end loop;
    output_line ('');
    output_line ('prompt ... done installing packages!');
    output_line ('');
  end if;

  output_file ('_install.sql');

  for i in 1 .. g_package_count loop

     output_line ('create or replace package ' || g_package_list(i).package_name);
     output_line ('as');
     output_line ('');
     generate_remarks (g_package_list(i).package_remarks);
     output_line ('');
     generate_subprogram_headers (g_package_list(i).subprogram_list);
     output_line ('');
     output_line ('end ' || g_package_list(i).package_name || ';');
     output_line ('/');
     output_line ('');
     output_line ('');
     output_file (g_package_list(i).package_name || '.pks');
 
     output_line ('create or replace package body ' || g_package_list(i).package_name);
     output_line ('as');
     output_line ('');
     generate_remarks (g_package_list(i).package_remarks);
     output_line ('');
     generate_subprogram_bodies (g_package_list(i).subprogram_list);
     output_line ('');
     output_line ('end ' || g_package_list(i).package_name || ';');
     output_line ('/');
     output_line ('');
     output_line ('');
     output_file (g_package_list(i).package_name || '.pkb');
 
  end loop;

end generate_output;


procedure set_global_settings (p_author_initials in varchar2)
as
begin
  g_global_settings.author_initials := p_author_initials;
end set_global_settings;


procedure generate_code (p_text in varchar2)
as
begin

  init_gen (p_text);
  generate_output;
  finish_gen;

end generate_code;


procedure download_code (p_text in varchar2,
                         p_output_mode in varchar2 := null)
as
  l_file_content   blob;
  l_mime_type      varchar2(255);
  l_file_name      varchar2(255);
begin
 
  /*
  
  Purpose:    download code
  
  Remarks:    
  
  Date        Who  Description
  ----------  ---  -------------------------------------
  31.07.2018  MBR  Created
  
  */
 
  g_output_mode := nvl(p_output_mode, g_output_mode_script);

  init_gen (p_text);
  generate_output;
  finish_gen;

  if g_output_mode = g_output_mode_zip then
    l_file_content := g_output_zip;
    l_file_name := 'quickplsql_' || to_char(sysdate, 'yyyymmddhh24miss') || '.zip';
    l_mime_type := 'application/zip';
  else
    l_file_content := sql_util_pkg.clob_to_blob (g_output_clob);
    l_file_name := 'quickplsql_' || to_char(sysdate, 'yyyymmddhh24miss') || '.sql';
    l_mime_type := 'text/plain';
  end if;

  owa_util.mime_header(l_mime_type, false);
  htp.p('Content-length: ' || dbms_lob.getlength(l_file_content));
  htp.p('Content-Disposition: attachment; filename="' || l_file_name || '"');
  owa_util.http_header_close;
    
  wpg_docload.download_file (l_file_content);

  apex_application.stop_apex_engine;
 
end download_code;


end codegen_quickplsql_pkg;
/

