#!/bin/bash

 

usage () {

  echo "

  A wrapper script around tc/netem for causing traffic problems in New Jersey (or anywhere else).

  Options:

    interface:  the network interface to mess with (eth0, bond0) or ALL to make everyone equally miserable

    ports:      a comma separated list of the TCP/IP ports to affect (optional)

    hosts:      a comma separated list of the IP addresses to affect (optional)

    delay:      # of milliseconds to delay packets

    block:      stop packets entirely by setting the loss rate to 100%

    direction:  IN for inbound traffic, OUT for outbound or BOTH for both.

                Note: be sure to use the --server param if needed.

    server:     This is a little tricky.  You must set this flag if you are shaping traffic for an

                application running on THIS host which accepts connections on the specified port.

                If WE are the server, then inbound traffic on our port will list US as the packet's 'destination'.

                The 'destination' and 'source' ports/hosts need to be reversed under the hood when

                messing with a local server.  See examples on how to set this parameter or how to mess

                with only one particular inbound connection to the local server.

    disable:    return network traffic to normal state

    preview:    display the tc/netem commands to be run but don't run them.

    show:       list any traffic shaping rules currently in effect.  The normal state is to have one pfifo_fast

                queue on each interface.

 

  bridgegate.sh -i|--interface [interface name or ALL] -p|--ports [PORT1,PORT2] -h|--hosts [HOST1,HOST2] -d|--delay [DELAY milliseconds] -r|--direction [IN|OUT|BOTH] -x|--disable -s|--show -b|--block -w|--preview -e|--server

  Examples:

    * To make your web browser slow to request pages

      bridgegate.sh --interface ALL --ports 80 --delay 3000 --direction OUT

 

    * To slow down receipt of responses from a remote web server

      bridgegate.sh --interface ALL --ports 80 --delay 3000 --direction IN

 

    * To make your web server slow to receive all incoming requests

      bridgegate.sh --interface ALL --ports 80 --delay 3000 --direction IN --server

 

    * To make your web server slow to send all responses

      bridgegate.sh --interface ALL --ports 80 --delay 3000 --direction OUT  --server

 

    * To slow down one particular connection to your server app without affecting anyone else.  First use tcpdump to look up the temporary port assigned to that connection.  E.G. if you had an ssh server listening on port 22 and someone was connected and given the temporary port 12345

      bridgegate.sh --interface ALL --ports 12345 --delay 3000 --direction BOTH

" >&2

}

 

printRun() {

  if [[ $PREVIEW ]] ; then

    echo "$1"

  else

    eval "$1"

  fi

}

 

if [[ ! $1 ]] ; then

  usage

  exit 1

fi

 

OPTS=`getopt -o i:p:h:d:r:xsbew --long interface:,ports:,hosts:,delay:,direction:,disable,show,block,server,preview,help -n 'parse-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options.  Use --help for usage instructions." >&2 ; exit 1 ; fi

 

eval set -- "$OPTS"

 

INTERFACE=""

PORTS=""

HOSTS=""

DELAY=""

DIRECTION=""

STOP_SHAPING=0

SHOW=0

BLOCK=""

SERVER=0

NETEM=""

PORT_TYPE=""

PREVIEW=""

 

while true; do

  case $1 in

    -i | --interface ) INTERFACE=$2;   shift 2 ;;

    -p | --ports     ) PORTS=$2;       shift 2 ;;

    -h | --hosts     ) HOSTS=$2;       shift 2 ;;

    -d | --delay     ) DELAY=$2;       shift 2 ;;

    -r | --direction ) DIRECTION=$2;   shift 2 ;;

    -s | --show      ) SHOW=1;         shift   ;;

    -x | --disable   ) STOP_SHAPING=1; shift   ;;

    -b | --block     ) BLOCK=1;        shift   ;;

    -e | --server    ) SERVER=1;       shift   ;;

    -w | --preview   ) PREVIEW=1;      shift   ;;

    --help           ) usage;          exit 0  ;;

    :                ) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;

    --               ) shift; break ;;

    *                ) break ;;

  esac

done

 

IFS=',' read -ra PORTS <<< "$PORTS"

IFS=',' read -ra HOSTS <<< "$HOSTS"

 

if [[ ! $(command -v tc) && ! $PREVIEW ]] ; then

  echo "tc is not installed"

  exit 1

fi

 

if [[ ! $INTERFACE ]] ; then

  echo "Specify the interface (E.G. eth0, bond0) to delay using -i or --interface.  Use ifconfig to list interfaces or specify ALL to affect all interfaces"

  exit 1

elif [[ $INTERFACE == "ALL" ]] ; then

  INTERFACE=$(ls /sys/class/net | grep -v bond)

fi

 

if [[ $SHOW == 1 ]] ; then

  for i in $INTERFACE; do

    echo Interface $i:

    printRun "tc -p qdisc show dev $i"

    printRun "tc -p filter show dev $i"

  done

 

  exit

fi

 

if [[ $STOP_SHAPING == 1 ]] ; then

  #Just remove all defined queues and let the interfaces return to the default pfifo_fast

  for i in $INTERFACE; do

    if [[ ! $PREVIEW ]] ; then

      echo "Shaping stopped at $(date)"

      echo "Stopping traffic shaping on interface $i"

  fi

    if tc qdisc show dev $i | grep root > /dev/null; then

      printRun "tc qdisc del dev $i root"

    fi

    if tc qdisc show dev $i | grep ingress > /dev/null; then

      printRun "tc qdisc del dev $i ingress"

    fi

  done

  printRun "modprobe -r ifb"

  exit 1

fi

 

if [[ ! $PORTS && ! $HOSTS ]] ; then

  echo "Specify either the ports or the host/IP addresses to affect or both using -p or --ports and/or -h or --hosts"

  exit 1

fi

 

if [[ ! $DELAY && ! $BLOCK ]] ; then

  echo "Specify a delay in milliseconds using -d or --delay or block ports entirely with -b or --block"

  exit 1

elif [[ $BLOCK == 1 ]] ; then

  NETEM="loss 100%"

else

  NETEM="delay ${DELAY}ms"

fi

 

if [[ ! $DIRECTION =~ IN|OUT|BOTH ]] ; then

  echo "Specify if you want to delay traffic that is inbound, outbound, or both using -r or --direction IN|OUT|BOTH"

  exit 1

fi

 

if [[ $DIRECTION =~ IN|BOTH && $INTERFACE =~ bond.* ]] ; then

  echo "Ingress filtering on bonded interfaces is not supported."

  exit 1

fi

 

if [[ ! $PREVIEW ]] ; then

  echo "WARNING!!!! DO NOT FORGET TO TURN THIS OFF WHEN YOU ARE FINISHED"

  echo "Delaying hosts ${HOSTS[@]} on ports ${PORTS[@]} for $DELAY milliseconds in direction: $DIRECTION"

  echo "Shaping started at $(date)"

fi

 

for i in $INTERFACE; do

 

  #A qdisc (queueing discipline) is just a queue holding packets for delivery to the NIC

  #Under normal conditions there are no named queues defined (a pfifo_fast queue is used by default)

  #First we add a simple queue at the root of the NIC with type "prio" (prioritizing) and the name (handle) 1:

 

  if [[ $DIRECTION == "IN" || $DIRECTION == "BOTH" ]] ; then

    ingressDevice=$(echo $i | sed s/eth/ifb/)

    printRun "modprobe ifb"

    printRun "ip link set dev $ingressDevice up"

    printRun "tc qdisc add dev $i ingress"

    printRun "tc qdisc add dev $ingressDevice root netem ${NETEM}"

    if [[ $HOSTS ]] ; then

      for host in ${HOSTS[@]}; do

        if [[ $SERVER == 1 ]] ; then

          ADDR_TYPE="dst"

        else

          ADDR_TYPE="src"

        fi

        HOST_FILTER="match ip $ADDR_TYPE $host"

        if [[ ! $PORTS ]] ; then

          #Only hosts were specified so create filters for each host

          printRun "tc filter add dev $i parent ffff: protocol ip u32 $HOST_FILTER 0xffff flowid 1:1 action mirred egress redirect dev $ingressDevice"

        else

          #Both hosts and ports were specified so create filters for each host:port combination

          for port in ${PORTS[@]}; do

            if [[ $SERVER == 1 ]] ; then

              PORT_TYPE="dport"

            else

              PORT_TYPE="sport"

            fi

            PORT_FILTER="match ip $PORT_TYPE $port"

            printRun "tc filter add dev $i parent ffff: protocol ip u32 $HOST_FILTER $PORT_FILTER 0xffff flowid 1:1 action mirred egress redirect dev $ingressDevice"

          done

        fi

      done

    else

      #Only ports were specified so create filters for each port

      for port in ${PORTS[@]}; do

        if [[ $SERVER == 1 ]] ; then

          PORT_TYPE="dport"

        else

          PORT_TYPE="sport"

        fi

        PORT_FILTER="match ip $PORT_TYPE $port"

        printRun "tc filter add dev $i parent ffff: protocol ip u32 $PORT_FILTER 0xffff flowid 1:1 action mirred egress redirect dev $ingressDevice"

      done

    fi

  fi

  if [[ $DIRECTION == "OUT" || $DIRECTION == "BOTH" ]] ; then

    printRun "tc qdisc add dev $i root handle 1: prio priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"

    printRun "tc qdisc add dev $i parent 1:2 handle 20: netem ${NETEM}"

    if [[ $HOSTS ]] ; then

      for host in ${HOSTS[@]}; do

        if [[ $SERVER == 1 ]] ; then

          ADDR_TYPE="src"

        else

          ADDR_TYPE="dst"

        fi

        HOST_FILTER="match ip $ADDR_TYPE $host"

        if [[ ! $PORTS ]] ; then

          #Only hosts were specified so create filters for each host

          printRun "tc filter add dev $i parent 1:0 protocol ip u32 $HOST_FILTER 0xffff flowid 1:2"

        else

          #Both hosts and ports were specified so create filters for each host:port combination

          for port in ${PORTS[@]}; do

            if [[ $SERVER == 1 ]] ; then

              PORT_TYPE="sport"

            else

              PORT_TYPE="dport"

            fi

            PORT_FILTER="match ip $PORT_TYPE $port"

            printRun "tc filter add dev $i parent 1:0 protocol ip u32 $HOST_FILTER $PORT_FILTER 0xffff flowid 1:2"

          done

        fi

      done

    else

      #Only ports were specified so create filters for each port

      for port in ${PORTS[@]}; do

        if [[ $SERVER == 1 ]] ; then

          PORT_TYPE="sport"

        else

          PORT_TYPE="dport"

        fi

        PORT_FILTER="match ip $PORT_TYPE $port"

        printRun "tc filter add dev $i parent 1:0 protocol ip u32 $PORT_FILTER 0xffff flowid 1:2"

      done

    fi

  fi

done