(* yelu-lsp — language server for .yc, over linol-lwt.

   M1.5a: textDocument/formatting via Yc_driver.format (the same engine as
   `yelu fmt`) + parse diagnostics. Hover / semantic tokens / richer
   diagnostics to follow. See doc/lang/surface_status.md. *)

open Lsp.Types

let format_src = Yelu_langs.Yc_driver.format

(* Whole-document range, for a full-text replace edit. *)
let whole_range (content : string) : Range.t =
  let lines = String.split_on_char '\n' content in
  let last_line = max 0 (List.length lines - 1) in
  let last_col =
    match List.rev lines with [] -> 0 | l :: _ -> String.length l
  in
  Range.create
    ~start:(Position.create ~line:0 ~character:0)
    ~end_:(Position.create ~line:last_line ~character:last_col)

(* 0-based (line, character) of a byte offset into [content]. *)
let offset_to_position (content : string) (offset : int) : Position.t =
  let n = String.length content in
  let offset = if offset < 0 then 0 else if offset > n then n else offset in
  let line = ref 0 and col = ref 0 in
  for i = 0 to offset - 1 do
    if content.[i] = '\n' then (incr line; col := 0) else incr col
  done;
  Position.create ~line:!line ~character:!col

(* M1.5b: place the diagnostic at the offending token's span (parse errors);
   lex errors have no token span and fall back to the document start. *)
let parse_diagnostics (content : string) : Diagnostic.t list =
  match Yelu_langs.Yc_cst_parse.parse_with_pos content with
  | Ok _ -> []
  | Error { Yelu_langs.Yc_cst_parse.msg; at } ->
    let range =
      match at with
      | Some { Yelu_langs.Yelu_lexer.lo; hi } ->
        Range.create
          ~start:(offset_to_position content lo)
          ~end_:(offset_to_position content hi)
      | None ->
        Range.create
          ~start:(Position.create ~line:0 ~character:0)
          ~end_:(Position.create ~line:0 ~character:1)
    in
    [ Diagnostic.create ~range ~severity:DiagnosticSeverity.Error
        ~source:"yelu" ~message:(`String msg) () ]

(* Scan [content] for the first whole-word occurrence of [name] and return
   its byte range. Whole-word = bounded by non-identifier characters
   (or document edges). Falls back to [None] if not found — caller maps
   that to a document-start placeholder so the diagnostic still appears. *)
let find_word_range (content : string) (name : string) : Range.t option =
  let n = String.length content in
  let m = String.length name in
  let is_id c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') || c = '_' || c = '-'
  in
  let rec find i =
    if i + m > n then None
    else if (i = 0 || not (is_id content.[i - 1]))
         && (i + m = n || not (is_id content.[i + m]))
         && String.sub content i m = name
    then Some (Range.create
                 ~start:(offset_to_position content i)
                 ~end_:(offset_to_position content (i + m)))
    else find (i + 1)
  in
  find 0

(* Wellform diagnostics: run [Yc_wellform.check_all] over the lowered IR
   and convert each finding to an LSP Diagnostic. Severity tracks the
   compile/format gate: Enum_shadow / Positional_form / closed-world
   Unknown_command are errors (red curly); the rest are warnings (yellow).
   Spans are scanned out of the source text by whole-word match — a
   heuristic but practical until the IR carries spans (see
   surface_lsp_framework.md §7.5 follow-ups). *)
let wellform_diagnostics (content : string) : Diagnostic.t list =
  (* B1: use the unified Yc_driver.parse_and_check so the LSP, fmt, and
     compile all see the same findings (check_cst ∪ check_all). *)
  match Yelu_langs.Yc_driver.parse_and_check content with
  | Error _ -> []   (* parse_diagnostics already surfaces this *)
  | Ok { findings; _ } ->
    let doc_start () =
      Range.create
        ~start:(Position.create ~line:0 ~character:0)
        ~end_:(Position.create ~line:0 ~character:1)
    in
    let make ~severity ~name ~message =
      let range =
        match find_word_range content name with
        | Some r -> r | None -> doc_start ()
      in
      Diagnostic.create ~range ~severity
        ~source:"yelu" ~message:(`String message) ()
    in
    List.filter_map (fun (f : Yelu_langs.Yc_wellform.error) ->
      match f with
      | Yelu_langs.Yc_wellform.Enum_shadow { name; constructor } ->
        Some (make ~severity:DiagnosticSeverity.Error ~name
                ~message:(Printf.sprintf
                            "variable %S shadows the %s enum constructor; \
                             rename it (Y14)" name constructor))
      | Yelu_langs.Yc_wellform.Positional_form { command } ->
        Some (make ~severity:DiagnosticSeverity.Error ~name:command
                ~message:(Printf.sprintf
                            "`%s` in positional cmake-keyword form is not a \
                             yc surface; use the ~label= form or yc_raw '…'"
                            command))
      | Yelu_langs.Yc_wellform.Unknown_command { name; closed_world = true } ->
        Some (make ~severity:DiagnosticSeverity.Error ~name
                ~message:(Printf.sprintf
                            "unknown command %S — closed world (no include / \
                             find_package / add_subdirectory / cmake_call / \
                             dynamic fun-name). Did you mean `fun`/`function`/\
                             `macro`?" name))
      | Yelu_langs.Yc_wellform.Unknown_command { name; closed_world = false } ->
        Some (make ~severity:DiagnosticSeverity.Warning ~name
                ~message:(Printf.sprintf
                            "%S is not a typed yc primitive and is not declared \
                             in this file. If it's a cmake-stdlib or cross-file \
                             call, wrap it in `yc_raw '…'` to silence." name))
      | Yelu_langs.Yc_wellform.Raw_cmake_escape { text; reason } ->
        let preview =
          if String.length text > 60
          then String.sub text 0 57 ^ "…"
          else text
        in
        Some (Diagnostic.create
                ~range:(doc_start ())
                ~severity:DiagnosticSeverity.Information
                ~source:"yelu"
                ~message:(`String
                            (Printf.sprintf "raw cmake escape [%s]: %s"
                               reason preview)) ())
      | Yelu_langs.Yc_wellform.Reserved_name { name; context; conflict } ->
        Some (make ~severity:DiagnosticSeverity.Warning ~name
                ~message:(Printf.sprintf
                            "%s name %S collides with a %s" context name conflict))
      | Yelu_langs.Yc_wellform.Apply_shadows_primitive { name } ->
        Some (make ~severity:DiagnosticSeverity.Warning ~name
                ~message:(Printf.sprintf
                            "yc_apply on %S shadows the typed yc primitive — \
                             use the typed form instead" name))
      | Yelu_langs.Yc_wellform.Function_def_typo { name } ->
        Some (make ~severity:DiagnosticSeverity.Error ~name
                ~message:(Printf.sprintf
                            "`%s args (block)` — adjacent command + standalone \
                             block has no valid cmake reading. Did you mean \
                             `fun %s(args) (body)`?" name name))
      | Yelu_langs.Yc_wellform.Unknown_kwarg { command; key } ->
        Some (make ~severity:DiagnosticSeverity.Error ~name:("~" ^ key)
                ~message:(Printf.sprintf
                            "`%s` does not accept ~%s= — the argument would be \
                             silently dropped; check the label spelling"
                            command key)))
      findings

(* Combined diagnostics: parse errors take precedence (no point flagging
   wellform if the file doesn't parse). *)
let all_diagnostics (content : string) : Diagnostic.t list =
  let p = parse_diagnostics content in
  if p <> [] then p else wellform_diagnostics content

class lsp_server =
  object (self)
    inherit Linol_lwt.Jsonrpc2.server as super

    val buffers : (DocumentUri.t, string) Hashtbl.t = Hashtbl.create 32

    method spawn_query_handler f = Linol_lwt.spawn f

    method private _on_doc ~(notify_back : Linol_lwt.Jsonrpc2.notify_back)
        (uri : DocumentUri.t) (content : string) : unit Linol_lwt.t =
      Hashtbl.replace buffers uri content;
      notify_back#send_diagnostic (all_diagnostics content)

    method on_notif_doc_did_open ~notify_back d ~content : unit Linol_lwt.t =
      self#_on_doc ~notify_back d.uri content

    method on_notif_doc_did_change ~notify_back d _c ~old_content:_ ~new_content
        : unit Linol_lwt.t =
      self#_on_doc ~notify_back d.uri new_content

    method on_notif_doc_did_close ~notify_back:_ d : unit Linol_lwt.t =
      Hashtbl.remove buffers d.uri;
      Linol_lwt.return ()

    (* advertise textDocument/formatting *)
    method! config_modify_capabilities (c : ServerCapabilities.t)
        : ServerCapabilities.t =
      { c with documentFormattingProvider = Some (`Bool true) }

    (* formatting: full-document replace via Yc_driver.format; on parse
       failure return no edits (fail-safe — never corrupt the buffer). *)
    method! on_request_unhandled : type r.
        notify_back:Linol_lwt.Jsonrpc2.notify_back ->
        id:_ ->
        r Lsp.Client_request.t ->
        r Linol_lwt.t =
      fun ~notify_back ~id r ->
        match r with
        | Lsp.Client_request.TextDocumentFormatting params ->
          let uri = params.textDocument.uri in
          (match Hashtbl.find_opt buffers uri with
           | Some content ->
             (match format_src content with
              | Ok formatted ->
                Linol_lwt.return
                  (Some [ TextEdit.create ~range:(whole_range content)
                            ~newText:formatted ])
              | Error _ -> Linol_lwt.return None)
           | None -> Linol_lwt.return None)
        | _ -> super#on_request_unhandled ~notify_back ~id r
  end

let () =
  let s = new lsp_server in
  let server = Linol_lwt.Jsonrpc2.create_stdio ~env:() s in
  let task =
    let shutdown () = s#get_status = `ReceivedExit in
    Linol_lwt.Jsonrpc2.run ~shutdown server
  in
  match Linol_lwt.run task with
  | () -> ()
  | exception e ->
    Printf.eprintf "yelu-lsp error: %s\n%!" (Printexc.to_string e);
    exit 1
