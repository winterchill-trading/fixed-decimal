open! Core

(* The contents of each fenced block opened by a line ["```ocaml"]. *)
let ocaml_blocks markdown =
  let rec loop lines ~current ~acc =
    match lines, current with
    | [], _ -> List.rev acc
    | "```" :: rest, Some block ->
      loop rest ~current:None ~acc:(String.concat (List.rev block) ~sep:"\n" :: acc)
    | line :: rest, Some block -> loop rest ~current:(Some (line :: block)) ~acc
    | "```ocaml" :: rest, None -> loop rest ~current:(Some []) ~acc
    | _ :: rest, None -> loop rest ~current:None ~acc
  in
  loop (String.split_lines markdown) ~current:None ~acc:[]
;;

let () =
  match Sys.get_argv () with
  | [| _; readme; source |] ->
    let source_text = In_channel.read_all source in
    let blocks = ocaml_blocks (In_channel.read_all readme) in
    if List.is_empty blocks then failwithf "%s: no ocaml blocks found" readme ();
    let missing =
      List.filter blocks ~f:(fun block ->
        not (String.is_substring source_text ~substring:block))
    in
    if not (List.is_empty missing)
    then (
      List.iter missing ~f:(fun block ->
        eprintf "%s: block not found in %s:\n%s\n\n" readme source block);
      exit 1)
  | _ -> failwith "usage: check_readme.exe README.md test_readme.ml"
;;
