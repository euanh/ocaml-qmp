(*
 * Copyright (C) 2013 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

type greeting = {
  major: int;
  minor: int;
  micro: int;
  package: string;
}

type event = {
  timestamp: (int * int);
  event: string;
}

type enabled = {
  enabled: bool;
  present: bool;
}

type vnc = {
  enabled : bool;
  auth    : string;
  family  : string;
  service : int;
  host    : string;
}

type xen_platform_pv_driver_info = {
  product_num : int;
  build_num   : int;
}

type command =
  | Qmp_capabilities
  | Query_commands
  | Query_kvm
  | Query_status
  | Query_vnc
  | Query_xen_platform_pv_driver_info
  | Stop
  | Cont
  | Eject of string * bool option
  | Change of string * string * string option
  | System_powerdown
  | Xen_save_devices_state of string
  | Xen_load_devices_state of string
  | Xen_set_global_dirty_log of bool

type result =
  | Name_list of string list
  | Enabled of enabled
  | Status of string
  | Vnc of vnc
  | Xen_platform_pv_driver_info of xen_platform_pv_driver_info
  | Unit

type error = {
  cls: string;
  descr: string;
}

type id = string

type message =
  | Greeting of greeting
  | Command of (id option * command)
  | Error of (id option * error)
  | Success of (id option * result)
  | Event of event

module Event = struct

  (* Emitted when XEN PV driver write build number to io-port 0x10,
     marking the end of preamble:
   # <- { "event": "XEN_PLATFORM_PV_DRIVER_INFO",
   #      "data": { "product-num": 3, "build-num": 1},
   #      "timestamp": { "seconds": 1500394278, "microseconds": 878290 } }
  *)
  let _XEN_PLATFORM_PV_DRIVER_INFO = "XEN_PLATFORM_PV_DRIVER_INFO"
end


let message_of_string x =
  let int = function
  | `Int x -> x
  | _ -> failwith "int" in
  (* let float = function
  | `Int x -> float_of_int x
  | _ -> failwith "float" in *)
  let string = function
  | `String x -> x
  | _ -> failwith "string" in
  let assoc = function
  | `Assoc x -> x
  | _ -> failwith "assoc" in
  let bool = function
  | `Bool x -> x
  | _ -> failwith "bool" in
  match Yojson.Safe.from_string x with
  | `Assoc
     [ ("QMP", `Assoc [ ("version", `Assoc [ "qemu", `Assoc version; "package", `String package ]); ("capabilities", _)] )] ->
    Greeting {
      minor = int (List.assoc "minor" version);
      major = int (List.assoc "major" version);
      micro = int (List.assoc "micro" version);
      package = package;
    }
  | `Assoc list when List.mem_assoc "event" list ->
    let event = string (List.assoc "event" list) in
    let timestamp = assoc (List.assoc "timestamp" list) in
    let secs = int (List.assoc "seconds" timestamp) in
    let usecs = int (List.assoc "microseconds" timestamp) in
    Event { timestamp=(secs, usecs); event }
  | `Assoc list when List.mem_assoc "execute" list ->
    let id = if List.mem_assoc "id" list then Some (string (List.assoc "id" list)) else None in
    Command (id, (match string (List.assoc "execute" list) with
      | "qmp_capabilities" -> Qmp_capabilities
      | "stop" -> Stop
      | "cont" -> Cont
      | "system_powerdown" -> System_powerdown
      | "query-commands" -> Query_commands
      | "query-status" -> Query_status
      | "query-vnc" -> Query_vnc
      | "query-kvm" -> Query_kvm
      | "query-xen-platform-pv-driver-info" -> Query_xen_platform_pv_driver_info
      | "eject" ->
            let arguments = assoc (List.assoc "arguments" list) in
            Eject (string (List.assoc "device" arguments),
                   if List.mem_assoc "force" arguments then
                     Some (bool (List.assoc "force" arguments))
                   else
                     None)
      | "change" ->
          let arguments = assoc (List.assoc "arguments" list) in
            Change (string (List.assoc "device" arguments),
                    string (List.assoc "target" arguments),
                    if List.mem_assoc "arg" arguments then
                      Some (string (List.assoc "arg" arguments))
                    else None)
      | "xen-save-devices-state" -> Xen_save_devices_state (string (List.assoc "filename" (assoc (List.assoc "arguments" list))))
      | "xen-load-devices-state" -> Xen_load_devices_state (string (List.assoc "filename" (assoc (List.assoc "arguments" list))))
      | "xen-set-global-dirty-log" -> Xen_set_global_dirty_log (bool (List.assoc "enable" (assoc (List.assoc "arguments" list))))
      | x -> failwith (Printf.sprintf "unknown command %s" x)
    ))
  | `Assoc list when List.mem_assoc "return" list ->
    let id = if List.mem_assoc "id" list then Some (string (List.assoc "id" list)) else None in
    (match List.assoc "return" list with
      | `Assoc [] -> Success (id, Unit)
      | `Assoc list when List.mem_assoc "status" list ->
        Success (id, Status (string (List.assoc "status" list)))
      | `Assoc list when List.mem_assoc "enabled" list
                      && List.mem_assoc "auth" list && List.mem_assoc "family"  list
                      && List.mem_assoc "service" list && List.mem_assoc "host" list ->
        Success (id, Vnc (
          let enabled = bool (List.assoc "enabled" list)  in
          let auth = string (List.assoc "auth" list) in
          let family = string (List.assoc "family" list) in
          let service = int_of_string (string (List.assoc "service" list)) in
          let host = string (List.assoc "host" list) in
          {enabled; auth; family; service; host}))
      | `Assoc list when List.mem_assoc "product-num" list
                      && List.mem_assoc "build-num" list -> (
        try
          Success (id, Xen_platform_pv_driver_info (
            let product_num = int (List.assoc "product-num" list) in
            let build_num = int (List.assoc "build-num" list) in
            {product_num; build_num}))
        with e ->
          Error(None, { cls = "JSONParsing"; descr = (Printf.sprintf "%s:%s" (Printexc.to_string e) x) })
        )
      | `Assoc list when List.mem_assoc "enabled" list ->
        let enabled = bool (List.assoc "enabled" list) in
        let present = bool (List.assoc "present" list) in
        Success (id, Enabled {enabled; present})
      | `List ((`Assoc pair :: _) as list) when List.mem_assoc "name" pair ->
        Success (id, Name_list (List.map (function
                             | `Assoc [ "name", `String x ] -> x
                             | _ -> failwith "assoc") list))
      | x -> failwith (Printf.sprintf "unknown result %s" (Yojson.Safe.to_string x))
    )
  | `Assoc list when List.mem_assoc "error" list ->
    let id = if List.mem_assoc "id" list then Some (string (List.assoc "id" list)) else None in
    let error = assoc (List.assoc "error" list) in
    let cls = string (List.assoc "class" error) in
    let descr = string (List.assoc "desc" error) in
    Error (id, {cls; descr})
  | x ->
    failwith (Printf.sprintf "message_of_string %s" (Yojson.Safe.to_string x))

let json_of_message = function
  | Greeting { major; minor; micro; package } ->
    let version = [ "major", `Int major; "minor", `Int minor; "micro", `Int micro ] in
    `Assoc [ ("QMP", `Assoc [ ("version", `Assoc [ "qemu", `Assoc version; "package", `String package ]); ("capabilities", `List []) ])]
  | Command(id, cmd) ->
    let id = match id with None -> [] | Some x -> [ "id", `String x ] in
    let cmd, args = match cmd with
      | Qmp_capabilities -> "qmp_capabilities", []
      | Stop -> "stop", []
      | Cont -> "cont", []
      | System_powerdown -> "system_powerdown", []
      | Query_commands -> "query-commands", []
      | Query_status -> "query-status", []
      | Query_vnc -> "query-vnc", []
      | Query_kvm -> "query-kvm", []
      | Query_xen_platform_pv_driver_info -> "query-xen-platform-pv-driver-info", []
      | Eject (device, None) -> "eject", [ "device", `String device ]
      | Eject (device, Some force) -> "eject", [ "device", `String device; "force", `Bool force ]
      | Change (device, target, None) -> "change", [ "device", `String device; "target", `String target ]
      | Change (device, target, Some arg) -> "change", [ "device", `String device; "target", `String target; "arg", `String arg ]
      | Xen_save_devices_state filename -> "xen-save-devices-state", [ "filename", `String filename]
      | Xen_load_devices_state filename -> "xen-load-devices-state", [ "filename", `String filename]
      | Xen_set_global_dirty_log enable -> "xen-set-global-dirty-log", [ "enable", `Bool enable ]
    in
    let args = match args with [] -> [] | args -> [ "arguments", `Assoc args ] in
    `Assoc (("execute", `String cmd) :: id @ args)
  | Event {timestamp; event} ->
    let secs, usecs = timestamp in
    `Assoc [("event", `String event); ("timestamp", `Assoc [ "seconds", `Int secs; "microseconds", `Int usecs])]
  | Success(id, result) ->
    let id = match id with None -> [] | Some x -> [ "id", `String x ] in
    let result = match result with
      | Unit -> `Assoc []
      | Status s -> `Assoc [ "status", `String s ]
      | Enabled {enabled; present} -> `Assoc [ "enabled", `Bool enabled; "present", `Bool present ]
      | Name_list xs -> `List (List.map (fun x -> `Assoc [ "name", `String x ]) xs)
      | Vnc {enabled; auth; family; service; host} -> `Assoc [ "enabled", `Bool enabled; "auth", `String auth; "family", `String family; "service", `String (string_of_int service); "host", `String host ]
      | Xen_platform_pv_driver_info { product_num; build_num } -> `Assoc [ "product-num", `Int product_num; "build-num", `Int build_num; ]
     in
    `Assoc (("return", result) :: id)
  | Error(id, e) ->
    let id = match id with None -> [] | Some x -> [ "id", `String x ] in
    let e = `Assoc [ "class", `String e.cls; "desc", `String e.descr; "data", `Assoc [] ] in
    `Assoc (("error", e) :: id)

let string_of_message m = Yojson.Safe.to_string (json_of_message m)

