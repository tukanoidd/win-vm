#!/usr/bin/env nu

use std/log

def main [
  --version (-v): string = 11l,
  --ram_size (-r): filesize = 4GB,
  --cpu-cores (-c): int = 4,
  --disk-size (-d): filesize = 100GB,
  --arguments (-a): string = "-device usb-host,vendorid=0x1234,productid=0x1234",
  --disk-fmt (-f): string = "qcow2"
  --debug

  --username (-u): string = "docker",
  --password (-p): string

  --language (-l): string = "English",
  --region (-g): string = "nl-NL",
  --keyboard (-k): string = "en-US"

  --edition: string

  --resolution:string = "1920x1080"
] {
  if (".env" | path exists) {
    rm .env
  }

  def fs_to_str [sz: filesize]: nothing -> string {
    $sz | to text | str join " " | str replace "B" ""
  }

  mut envs: list<any> = [
    ["VERSION" $version]
    ["RAM_SIZE" (fs_to_str $ram_size)]
    ["CPU_CORES" ($cpu_cores | to text)]
    ["DISK_SIZE" (fs_to_str $disk_size)]
    ["ARGUMENTS" $"\"($arguments)\""]
    ["DISK_FMT" $disk_fmt]
    ["LANGUAGE" $language]
    ["REGION" $region]
    ["KEYBOARD" $keyboard]
  ]

  def maybe_add_env [
    name: string
    env_?: string
    if_exists?: closure
  ]: list<any> -> list<any> {
    if $env_ != null {
      ($if_exists)
    
      return ($in | append [[$name $env]])
    }

    $in
  }

  def if_add_env [
    expr: bool
    name: string
    val: string = "1"
  ]: list<any> -> list<any> {
    let val = (match $expr {
      true => $val,
      false => null
    });

    $in | maybe_add_env $name $val
  }

  $envs = ($envs
    | if_add_env $debug "DEBUG"
    | maybe_add_env "USERNAME" $username {($username | save -f ".usrname")}
    | maybe_add_env "PASSWORD" $password
    | maybe_add_env "EDITION" $edition)

  ($envs
    | each {|e| $"($e.0)=($e.1)"}
    | str join "\n"
    | save -f ".env")

  let env_file = ("./.env" | path expand)

  let run_task = (job spawn {
    if ("./docker_logs.txt" | path exists) {
      rm ./docker_logs.txt
    }
  
    docker compose --env-file $env_file up windows o+e> docker_logs.txt
  });

  if ($env | get -o ZELLIJ) != null {
    (zellij action new-pane
      -f -c
      --name $"($version) docker logs"
      -- tail -f docker_logs.txt)
  }
  
  print "To open remmina, press 'O'"
  print "To exit, press 'Q'"

  mut rdp_task = -1

  loop {
    let k = (input -s -n 1 -d "")

    if $k == 'q' {
      job kill $run_task
      break
    }
    
    if (($k == 'o') and ("./docker_logs.txt" | path exists)) {
      let $logs = (open docker_logs.txt)

      if ($logs | str contains "Windows started succesfully, visit") {
        let ps = (docker compose ps --format json | from json)

        let id = match ($ps | describe | str starts-with 'record') {
          true => $ps.ID,
          false => ($ps
            | find {$in.SERVICE == "windows"}
            | get 0
            | get ID) 
        };

        let ip = (docker inspect $id
          | from json
          | into record
          | get NetworkSettings
          | get Networks
          | flatten
          | into record
          | get IPAddress);

        if $rdp_task >= 0 {
          job kill $rdp_task
        }

        $rdp_task = (job spawn {
          remmina -c $"rdp://(open .usrname)@($ip)"
        });
      } else {
        log warning "Can't start rdesktop, windows hasn't booted up yet!"
      }
    } else {
      log warning "Either docker container hasn't started yet or rdesktop was already opened!"
    }
  }
}
