open Internal

(** {2 Definition of an Alphabet} *)

type code = int
type elt  = int

module CodeMap = Internal.IntMap
module CodeSet = Internal.IntSet
module CodeSetMap = Internal.IntSetMap

type combinations =
 {  comb_set : CodeSet.t CodeMap.t;
    set_comb : code CodeSetMap.t;
 }

type kind =
  | Sequential
  | BitFlag
  | Continuous
  | CombinationLevels of int

type symbols = {
  gap_sym : string;
  all_sym : string;
  missing_sym : string;
  orientation_sym : string;
  separators : string list;
  containers : (string * string) list;
}

type t =
  { kind      : kind;
    atomic    : CodeSet.t;
    name_code : code StringMap.t;
    code_name : string CodeMap.t;
    compliment: code CodeMap.t;
    comb_data : combinations;
    gap       : int option;
    missing   : int option;
    all       : int option;
    case      : bool;
    orientation : bool;
    symbols   : symbols;
  }


(** {2 Error Module} *)

module Error = struct
  type t = [
    | `Missing_State_Sequential_Alphabet of int
    | `Missing_Name_Sequential_Alphabet of int
    | `Alphabet_Size_Expectation of int * int 
    | `Missing_Gap_Element of int
    | `No_Gap_Character_Found of string
    | `No_All_Character_Found of string
    | `No_Missing_Character_Found of string
    | `Complement_Not_Bijective of int * int
    | `Polymorphisms_In_Continuous_Alphabet
    | `Polymorphisms_In_Sequential_Alphabet
    | `Unacceptable_Level_Argument of int
    | `Gap_Not_Atomic_BitFlag_Alphabet of int
    | `Illegal_Character of string
    | `Illegal_Code of int
    | `Alphabet_Size_Too_Large_For_BitFlag of int
    | `Insufficient_Level_To_Represent_States of int * CodeSet.t
  ]

  let to_string = function
    | `Missing_State_Sequential_Alphabet x ->
      Printf.sprintf "Missing state %d in Sequential Alphabet" x
    | `Missing_Name_Sequential_Alphabet x ->
      Printf.sprintf "Missing name %d in Sequential Alphabet" x
    | `Alphabet_Size_Expectation (x,y) ->
      Printf.sprintf "Alphabet size expected to be %d, actually %d" x y
    | `Missing_Gap_Element x ->
      Printf.sprintf "Expected gap code %d in set of codes" x
    | `No_Gap_Character_Found x ->
      Printf.sprintf "Expected gap character %s in set of names" x
    | `No_All_Character_Found x ->
      Printf.sprintf "Expected all character %s in set of names" x
    | `No_Missing_Character_Found x ->
      Printf.sprintf "Expected missing character %s in set of names" x
    | `Complement_Not_Bijective (x,y) ->
      Printf.sprintf "Expected complement of %d and %d to be bijective." x y
    | `Polymorphisms_In_Sequential_Alphabet ->
      Printf.sprintf "Sequential Alphabets do not have polymorphisms"
    | `Polymorphisms_In_Continuous_Alphabet ->
      Printf.sprintf "Continuous Alphabets do not have polymorphisms"
    | `Unacceptable_Level_Argument x ->
      Printf.sprintf "Level argument is %d, should be > 0" x
    | `Gap_Not_Atomic_BitFlag_Alphabet x ->
      Printf.sprintf "Gap character %d is not atomic (multiple bits set)" x
    | `Illegal_Character str ->
      Printf.sprintf "Cannot find character '%s' in alphabet" str
    | `Illegal_Code i ->
      Printf.sprintf "Cannot find character %d in alphabet" i
    | `Alphabet_Size_Too_Large_For_BitFlag x ->
      Printf.sprintf "The alphabet of %d elements is too large to convert to bit-flags" x
    | `Insufficient_Level_To_Represent_States (level, set) -> 
      Printf.sprintf "The state combination of %d is too large represent a state in level %d" (CodeSet.cardinal set) level
end

exception Error of Error.t


(** {2 Constants} *)

let default_gap         = "-"

let default_all         = "X"

let default_missing     = "?"

let default_orientation = "~"

let default_separators  = ["#"; "|"; "@"; " ";]

let default_containers  = [("{","}"); ("[","]"); ("(",")"); ("<",">");]

let default_symbols =
  { gap_sym = default_gap;
    all_sym = default_all;
    missing_sym = default_missing;
    orientation_sym = default_orientation;
    separators = default_separators;
    containers = default_containers;
  }

let empty_comb_data =
  { comb_set = CodeMap.empty; set_comb = CodeSetMap.empty; }

(** {2 Combination Functions} *)

let generate_combinational_elements ~level codes =
  let incr r = incr r; !r in
  let cross_product map1 map2 k =
    CodeMap.fold
      (fun _ v1 ->
        CodeMap.fold
          (fun _ v2 -> CodeMap.add (incr k) (CodeSet.union v1 v2))
          map2)
      map1
      CodeMap.empty
  and inverse map =
    CodeMap.fold (fun k v -> CodeSetMap.add v k) map CodeSetMap.empty
  and merge_maps =
    CodeMap.merge
      (fun _ v1 v2 -> match v1,v2 with
        | None, None | Some _, Some _ -> assert false
        | None, ((Some _) as x)
        | ((Some _) as x), None -> x)
  in
  let l = Array.make level CodeMap.empty in
  l.(0) <- CodeMap.fold (fun i _ a -> CodeMap.add i (CodeSet.singleton i) a)
                       codes CodeMap.empty;
  let code = ref (fst @@ CodeMap.max_binding l.(0)) in
  for i = 1 to level-1 do
    l.(i) <- cross_product l.(0) l.(i-1) code
  done;
  let comb_set = Array.fold_left merge_maps CodeMap.empty l in
  comb_set, inverse comb_set

let of_list ~states ~equates ~gap ~all ~missing ~orientation ~case ~kind : t =
  let combine_equates comb_data name_code = match kind with
    | Sequential ->
      (function [x] -> StringMap.find x name_code 
               | _  -> raise (Error `Polymorphisms_In_Sequential_Alphabet))
    | Continuous ->
      (fun _ -> raise (Error `Polymorphisms_In_Continuous_Alphabet))
    | CombinationLevels _ ->
      (fun xs ->
        let set =
          List.fold_left
            (fun acc x -> CodeSet.add (StringMap.find x name_code) acc)
            CodeSet.empty
            xs
        in
        CodeSetMap.find set comb_data.set_comb)
    | BitFlag ->
      (fun xs -> List.fold_left (fun x y -> (StringMap.find y name_code) lor x) 0 xs)
  in
  let add_one code_incr_fn ((cname,ncode,atomic),code) (name,_) =
    let name = if case then name else String.uppercase name in
    if StringMap.mem name cname
      then raise (Error (`Illegal_Character name))
      else (StringMap.add name code cname,
              CodeMap.add code name ncode,
                CodeSet.add code atomic), code_incr_fn code
  in
  let (name_code,code_name,atomic),_ = (* add all states and equates *)
    let initial_code,incr_code = match kind with
      | CombinationLevels _ | Sequential-> 0,(fun x -> x+1)
      | BitFlag                         -> 1,(fun x -> x lsl 1)
      | Continuous                      -> 0,(fun _ -> assert false)
    in
    List.fold_left
      (add_one incr_code)
      ((StringMap.empty,CodeMap.empty,CodeSet.empty),initial_code)
      states
  in
  let comb_data = match kind with
    | CombinationLevels level ->
        let comb,lists = generate_combinational_elements ~level code_name in
        {comb_set = comb; set_comb = lists;}
    | Sequential | Continuous -> empty_comb_data
    | BitFlag                 -> empty_comb_data
  in
  let name_code,code_name =
    List.fold_left (* add equates *)
      (fun (name_code,code_name) (k,vs) ->
        let v = combine_equates comb_data name_code vs in
        let name_code = StringMap.add k v name_code
        and code_name =
          if CodeMap.mem v code_name
            then code_name 
            else CodeMap.add v k code_name
        in
        name_code,code_name)
      (name_code,code_name)
      equates
  in
  let compliment = (* add compliments from states *)
    List.fold_left
      (fun acc -> function
        | (_,None) -> acc
        | (k,Some x) ->
          let k = StringMap.find k name_code in
          let x = try StringMap.find x name_code
                  with Not_found -> raise (Error (`Illegal_Character x))
          in
          CodeMap.add k x (CodeMap.add x k acc))
      CodeMap.empty
      states
  in
  let gap = match gap with
    | None   -> None
    | Some x ->
        let x = if case then x else String.uppercase x in
        try Some (StringMap.find x name_code)
        with Not_found -> raise (Error (`No_Gap_Character_Found x))
  and missing = match missing with
    | None   -> None
    | Some x ->
        let x = if case then x else String.uppercase x in
        try Some (StringMap.find x name_code)
        with Not_found -> raise (Error (`No_Missing_Character_Found x))
  and all = match all with
    | None   -> None
    | Some x ->
        let x = if case then x else String.uppercase x in
        try Some (StringMap.find x name_code)
        with Not_found -> raise (Error (`No_All_Character_Found x))
  in
  let a = {
    kind; orientation; case;
    code_name; name_code;
    compliment; comb_data;
    all; gap; missing; atomic;
    symbols = default_symbols; (** TODO: add mechanism to change this *)
  } in
  a


let combination_alphabet ~states ~equates ~gap ~all ~missing ~orientation ~case ~level : t =
  let kind = CombinationLevels level in
  of_list ~states ~equates ~gap ~all ~missing ~orientation ~case ~kind

let sequential_alphabet ~states ~equates ~gap ~all ~missing ~orientation ~case : t =
  let kind = Sequential in
  of_list ~states ~equates ~gap ~all ~missing ~orientation ~case ~kind

let bitflag_alphabet ~states ~equates ~gap ~all ~missing ~orientation ~case : t =
  let kind = BitFlag in
  of_list ~states ~equates ~gap ~all ~missing ~orientation ~case ~kind


(** {2 Basic Alphabets} *)

let continuous =
  { kind      = Continuous;
    atomic    = CodeSet.empty;
    name_code = StringMap.empty;
    code_name = CodeMap.empty;
    compliment= CodeMap.empty;
    gap       = None;
    missing   = None;
    all       = None;
    orientation = false;
    case      = false;
    comb_data = empty_comb_data;
    symbols   = default_symbols;
  }

let present_absent =
  let states = [("present", None); ("absent", None) ] in
  of_list ~states ~equates:[] ~gap:(Some "absent") ~missing:None ~all:None
          ~kind:Sequential ~orientation:false ~case:false

let dna =
  let states = [("A", Some "T"); ("C", Some "G");
                ("G", Some "C"); ("T", Some "A");
                (default_gap, None); ("X", None) ]
  and equates = [("0",["A"]);("1",["C"]);("2",["G"]);("3",["T"]);("4",["-"])] in
  of_list ~states ~equates ~gap:(Some default_gap) ~all:(Some "X")
          ~missing:(Some "X") ~kind:BitFlag ~orientation:false ~case:false

let nucleotides =
  let states =
    [("A",Some "T");("C",Some "G");("G",Some "C");("T",Some "A");(default_gap,None);]
  and equates =
    (** IUPAC polymorphism codes + indel polymorphism codes. *)
   [("M", ["A";"C"]);         ("R", ["A";"G"]);         ("W", ["A";"T"]);
    ("S", ["G";"C"]);         ("Y", ["T";"C"]);         ("K", ["G";"T"]);
    ("V", ["G";"T";"C"]);     ("H", ["G";"T";"A"]);     ("D", ["C";"T";"A"]);
    ("B", ["G";"C";"A"]);     ("N", ["A";"C";"G";"T"]); ("X", ["A";"C";"G";"T"]);
    ("1", ["T";"-"]);         ("2", ["G";"-"]);         ("3", ["G";"T";"-"]);
    ("4", ["C";"-"]);         ("5", ["T";"C";"-"]);     ("6", ["G";"C";"-"]);
    ("7", ["G";"T";"C";"-"]); ("8", ["A";"-"]);         ("9", ["T";"A";"-"]);
    ("0", ["G";"A";"-"]);     ("E", ["G";"T";"A";"-"]); ("F", ["A";"C";"-"]);
    ("I", ["T";"A";"C";"-"]); ("J", ["G";"A";"C";"-"]); ("P", ["G";"T";"A";"C";"-"]);
    (default_missing, ["G";"T";"A";"C";"-"])]
  in
  of_list ~states ~equates ~gap:(Some default_gap) ~missing:(Some default_missing)
          ~all:(Some default_missing) ~kind:BitFlag ~orientation:false ~case:false

let aminoacids =
  let states = [
    ("A",None); (* alanine *)     ("R",None); (* arginine *)
    ("N",None); (* asparagine *)  ("D",None); (* aspartic *)
    ("C",None); (* cysteine *)    ("Q",None); (* glutamine *)
    ("E",None); (* glutamic *)    ("G",None); (* glycine *)
    ("H",None); (* histidine *)   ("I",None); (* isoleucine *)
    ("L",None); (* leucine *)     ("K",None); (* lysine *)
    ("M",None); (* methionine *)  ("F",None); (* phenylalanine *)
    ("P",None); (* proline *)     ("S",None); (* serine *)
    ("T",None); (* threonine *)   ("W",None); (* tryptophan *)
    ("Y",None); (* tyrosine *)    ("V",None); (* valine *)
    ("X",None); (* all element *) (default_gap,None); (* gap *)
  ] in
  of_list ~states ~equates:[] ~gap:(Some default_gap) ~all:(Some "X")
          ~missing:(Some "X") ~kind:Sequential ~orientation:false ~case:false


let generate_seq_alphabet ?(gap=true) ?(missing=false) n =
  let n = n - 1 in (* indexed at 0. *)
  let rec num_output n = if n > 10 then 1 + (num_output (n/10)) else 1 in
  let w = num_output n in
  let states = List.map (fun k -> (Printf.sprintf "%0*d" w k,None)) (0 -- n) in
  let xstates,gap,missing =
    let xs,gap = if gap then [(default_gap,None)],Some default_gap else [],None in
    let xs,mis = if missing then (default_missing,None)::xs,Some default_missing else xs,None in
    xs, gap, mis
  in
  let states = match xstates with | [] -> states | xs -> states @ xs
  and orientation = false and case = false and kind = Sequential and all = None in
  of_list ~states ~equates:[] ~gap ~all ~missing ~kind ~orientation ~case


(** {2 Basic Functions for querying alphabets *)

let size t =
  CodeSet.cardinal t.atomic

let is_statebased t = match t.kind with
  | CombinationLevels _
  | Sequential
  | Continuous -> true
  | BitFlag -> false

let is_bitflag t = match t.kind with
  | CombinationLevels _
  | Sequential
  | Continuous -> false
  | BitFlag -> true

let complement i t =
  if CodeMap.mem i t.compliment
    then Some (CodeMap.find i t.compliment)
    else None

let is_complement a b t =
  let is_complement a b t =
    if CodeMap.mem a t.compliment
      then ((CodeMap.find a t.compliment) = b)
      else false
  in
  let result = is_complement a b t in
  if result = is_complement b a t
    then result
    else raise (Error (`Complement_Not_Bijective (a,b)))

let is_gap n t = match t.gap with
  | Some x when x = n -> true
  | None | Some _ -> false

let get_code n t = match t.kind with
    | Continuous -> int_of_string n
    | BitFlag | CombinationLevels _ | Sequential ->
      let n = if t.case then n else String.uppercase n in
      try StringMap.find n t.name_code
      with Not_found -> raise (Error (`Illegal_Character n))

let get_name c t = match t.kind with
    | Continuous -> string_of_int c
    | BitFlag | CombinationLevels _ | Sequential ->
      try CodeMap.find c t.code_name
      with Not_found -> raise (Error (`Illegal_Code c))

let rec random ?(indel=false) t =
  let k,_ = random_elt_intmap t.code_name in
  if indel || not @@ is_gap k t then k else random ~indel t


(** {2 Polymorphism Management Functions} *)

(** return the number defining the maximum number of states contained in a
    polymorphism of the alphabet. *)
let max_polymorphism t = match t.kind with
  | CombinationLevels l -> l
  | Sequential          -> 1
  | Continuous          -> 1
  | BitFlag             -> size t

(** Return the states of a single alphabetic character. *)
let get_combination i t : CodeSet.t = match t.kind with
  | CombinationLevels _ -> CodeMap.find i t.comb_data.comb_set
  | Sequential when CodeSet.mem i t.atomic -> CodeSet.singleton i
  | Sequential -> raise (Error (`Illegal_Code i))
  | Continuous -> CodeSet.singleton i
  | BitFlag    ->
    BitSet.to_set (`Packed i)
      |> flip (CodeSet.fold (fun x -> CodeSet.add @@ (1 lsl (x-1)))) CodeSet.empty

(** Return the polymorphism from a set of states; with exception *)
let get_state_combination_exn s t : code = match t.kind with
  | CombinationLevels l when l >= CodeSet.cardinal s -> CodeSetMap.find s t.comb_data.set_comb
  | Sequential ->
      if 1 = CodeSet.cardinal s then
        let i = CodeSet.choose s in
        if CodeSet.mem i t.atomic then i else raise (Error (`Illegal_Code i))
      else
        raise (Error (`Insufficient_Level_To_Represent_States (1,s)))
  | Continuous when 1 = CodeSet.cardinal s -> CodeSet.choose s
  | BitFlag    -> CodeSet.fold (+) s 0
  | Continuous -> raise (Error `Polymorphisms_In_Continuous_Alphabet)
  | CombinationLevels l -> 
      raise (Error (`Insufficient_Level_To_Represent_States (l,s)))

(** return a polymorphism from a set of states, only if they can be represented *)
let get_state_combination s t =
  try get_state_combination_exn s t |> some with
  | Error (`Polymorphisms_In_Continuous_Alphabet)
  | Error (`Insufficient_Level_To_Represent_States _) -> None

(** Return a list of atomic elements from a list of elements. Each are exploded
    to their constituents and combined thus [ab] + [bc] -> [a;b;c] *)
let explode_polymorphisms l t =
  List.fold_left (fun a x -> CodeSet.union a (get_combination x t)) CodeSet.empty l |> CodeSet.elements

(** compress a list of states to a polymorphism; these are truncated by the
    maximum polymorphism available to the system. *)
let compress_polymorphisms l t =
  explode_polymorphisms l t |> take (max_polymorphism t) |>
    List.fold_left (flip CodeSet.add) CodeSet.empty |> flip get_state_combination_exn t

(** returns true if the element of the alphabet is atmoic / not a polymorphism *)
let is_atomic i t = match t.kind with
  | Sequential when CodeSet.mem i t.atomic -> true
  | Continuous -> true
  | CombinationLevels _
  | BitFlag -> 1 = CodeSet.cardinal @@ get_combination i t
  | Sequential -> raise (Error (`Illegal_Code i))


(** {2 Special Comparison Functions} *)

(** Can one alphabet simulate the states of another completely? *)
let compare_elts a b =
  StringMap.fold
    (fun k _ acc -> acc && (StringMap.mem k b.name_code))
    a.name_code
    true

(** compare kind, element encoding, and gap/missing/all/case/orientation status *)
let compare a b =
  let prop_compare =
    a.gap = b.gap && a.missing = b.missing && a.all = b.all && a.case = b.case
      && a.orientation = b.orientation && a.kind = b.kind
  in
  prop_compare && compare_elts a b


(** {2 Converting between types of alphabets} *)

let rec to_sequential t =
  let opt_find = function
    | None -> None
    | Some x -> Some (CodeMap.find x t.code_name)
  in
  match t.kind with
  | Sequential
  | Continuous -> t
  | BitFlag ->
    let states =
      CodeMap.fold
        (fun code name lst ->
          let cmp = opt_find @@ complement code t in
          (name,cmp) :: lst)
        t.code_name
        []
      |> List.rev
    and gap = opt_find t.gap and all = opt_find t.all
    and missing = opt_find t.missing in
    of_list ~states ~equates:[] ~gap ~all ~missing ~kind:Sequential
            ~orientation:t.orientation ~case:t.case
  | CombinationLevels _ ->
    let states =
      CodeMap.fold
        (fun code name lst ->
          if 1 = (CodeSet.cardinal @@ CodeMap.find code t.comb_data.comb_set)
            then (name,opt_find @@ complement code t)::lst
            else lst)
        t.code_name
        []
      |> List.rev
    in
    of_list ~states ~equates:[] ~gap:(opt_find t.gap) ~all:(opt_find t.all)
      ~missing:(opt_find t.missing) ~kind:Sequential ~orientation:t.orientation ~case:t.case

and to_bitflag t = match t.kind with
  | Continuous
  | BitFlag -> t
  | CombinationLevels _ -> to_bitflag (to_sequential t)
  | Sequential ->
    let opt_find = function
      | None -> None
      | Some x -> Some (CodeMap.find x t.code_name)
    in
    let states =
      CodeMap.fold
        (fun code name lst ->
          let cmp  = match complement code t with
            | None -> None
            | Some x -> Some (CodeMap.find x t.code_name)
          in
          (name,cmp)::lst)
        t.code_name
        []
      |> List.rev
    in
    of_list ~states ~equates:[] ~gap:(opt_find t.gap) ~all:(opt_find t.all)
      ~missing:(opt_find t.missing) ~kind:BitFlag ~orientation:t.orientation ~case:t.case

(** Convert the alphabet to sequential or simple bitflag formats. *)
and simplify t = match t.kind with
  | CombinationLevels _ -> to_sequential t
  | Sequential | BitFlag | Continuous -> t

(** Converts the alphabet to a level specified, where level 1 = sequential. *)
and to_level level t =
  let () = if level <= 0 then raise (Error (`Unacceptable_Level_Argument level)) in
  match t.kind with
  | _                   when level = 1 -> to_sequential t
  | CombinationLevels l when level = l -> t
  | Continuous                         -> t
  | BitFlag
  | CombinationLevels _                -> to_level level (to_sequential t)
  | Sequential ->
    let combs,lsts = generate_combinational_elements ~level t.code_name in
    let comb_data = {comb_set = combs; set_comb = lsts;} in
    {t with
      kind = CombinationLevels level; comb_data; }

let pp_alphabet fmt t =
  Format.(
    let pp_print_option fmt = function
      | None -> pp_print_string fmt "None"
      | Some i -> pp_print_int fmt i
    and pp_tab_name fmt n =
      pp_print_tab fmt ();
      pp_print_string fmt n;
      pp_print_tab fmt ();
    in
    pp_open_tbox fmt ();
    pp_set_tab fmt ();
    (* match width of    orientation *)
    pp_print_string fmt "Kind       ";
    pp_print_string fmt begin match t.kind with
      | BitFlag -> "Bit Flag"
      | Sequential -> "Sequential"
      | Continuous -> "Continuous"
      | CombinationLevels k -> "Level "^(string_of_int k)
    end;
    pp_tab_name fmt "Gap";         pp_print_option fmt t.gap;
    pp_tab_name fmt "Missing";     pp_print_option fmt t.missing;
    pp_tab_name fmt "All";         pp_print_option fmt t.all;
    pp_tab_name fmt "Case";        pp_print_bool fmt t.case;
    pp_tab_name fmt "Orientation"; pp_print_bool fmt t.orientation;
    pp_tab_name fmt "States : ";
    pp_open_hbox fmt ();
      CodeSet.iter (fprintf fmt "%d @,") t.atomic;
    pp_close_box fmt ();
    pp_close_tbox fmt ());
  ()

