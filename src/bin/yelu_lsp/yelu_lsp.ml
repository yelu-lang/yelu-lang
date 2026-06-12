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

class lsp_server =
  object (self)
    inherit Linol_lwt.Jsonrpc2.server as super

    val buffers : (DocumentUri.t, string) Hashtbl.t = Hashtbl.create 32

    method spawn_query_handler f = Linol_lwt.spawn f

    method private _on_doc ~(notify_back : Linol_lwt.Jsonrpc2.notify_back)
        (uri : DocumentUri.t) (content : string) : unit Linol_lwt.t =
      Hashtbl.replace buffers uri content;
      notify_back#send_diagnostic (parse_diagnostics content)

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
