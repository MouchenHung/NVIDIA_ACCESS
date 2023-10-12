#!/bin/bash

APP_NAME="NVIDIA DEVICE ACCESS TOOL"
APP_VERSION="1.1.0"
APP_DATE="2023/09/21"
APP_AUTH="Mouchen"

I2C_1="0x09" #for FPGA/GPU
I2C_2="0x0a" #for FPGA/HMC/NVSWITCH

GPU1_ADDR="0x88"
GPU2_ADDR="0x8a"
GPU3_ADDR="0x8c"
GPU4_ADDR="0x8e"
GPU5_ADDR="0x98"
GPU6_ADDR="0x9a"
GPU7_ADDR="0x9c"
GPU8_ADDR="0x9e"

FPGA_ADDR="0xc0"
HMC_ADDR="0xa8"

SMBPBI_REG_CS="0x5c"
SMBPBI_REG_DATA="0x5d"

SMBPBI_OPCODE_CAP="0x01"
SMBPBI_OPCODE_S_TEMP="0x02"
SMBPBI_OPCODE_E_TEMP="0x03"
SMBPBI_OPCODE_INT_STAT="0x11"
SMBPBI_OPCODE_FENCE="0xa3"

MODE_SMBPBI="smbpbi"
MODE_DIRECT="direct"

mode=$MODE_SMBPBI
i2c_bus="9"
device_addr="0"
command=""
read_num=1
wr_data=""

# --------------------------------- SERVER lib --------------------------------- #
IPMI_NETFN_SENSOR=0x04
IPMI_CMD_GET_SENSOR_READING=0x2d
IPMI_NETFN_APP=0x06
IPMI_CMD_GET_DEVICE_ID=0x01
IPMI_NETFN_STORAGE=0x0A

SERVER_IP="10.10.11.78"
USER_NAME="admin"
USER_PWD="admin"
ipmi_cmd_prefix=""
ipmi_raw_cmd_prefix=""
ipmi_init_success=0

SERVER_INIT(){
	server_ip=$1
	user_name=$2
	user_pwd=$3
	echo "{Server info}"
	echo "* ip:       $server_ip"
	echo "* user:     $user_name"
	echo "* password: $user_pwd"
	echo ""
	ipmi_cmd_prefix="ipmitool -H $server_ip -U $user_name -P $user_pwd"
	ipmi_raw_cmd_prefix="$ipmi_cmd_prefix raw"

	#Pre-test
	ipmi_init_success=1
	IPMI_RAW_SEND $IPMI_NETFN_APP $IPMI_CMD_GET_DEVICE_ID
	if [ $? == 1 ]; then
		echo "[ERR] Failed to init server!"
		ipmi_init_success=0
	fi	
}

response_msg=""
IPMI_RAW_SEND(){
	if [ $ipmi_init_success == 0 ]; then
		echo "[ERR] ipmi init not ready!"
		response_msg=""
		return 1
	fi

	ret=0
	netfn=$1
	cmd=$2
	data=$3
	rsp=`$ipmi_raw_cmd_prefix $netfn $cmd $data`
	if [ $? == 1 ]; then
		ret=1
	fi
	#echo "output:"
	#echo $rsp
	response_msg=$rsp

	return $ret
}

IPMI_SEND(){
	if [ $ipmi_init_success == 0 ]; then
		echo "[ERR] ipmi init not ready!"
		response_msg=""
		return 1
	fi

	op=$1

	#command list if op=0
	#extend command list if op>0
	cmd_list=$2

	if [ $op == 0 ]; then
		ipmi_cmd_prefix $cmd_list
	elif [ $op == 1 ]; then
		ipmi_cmd_prefix mc info $cmd_list
	elif [ $op == 2 ]; then
		ipmi_cmd_prefix sdr list $cmd_list
	elif [ $op == 3 ]; then
		ipmi_cmd_prefix sensor list $cmd_list
	elif [ $op == 3 ]; then
		ipmi_cmd_prefix sel list $cmd_list
	elif [ $op == 3 ]; then
		ipmi_cmd_prefix sel clear $cmd_list
	fi
}
# --------------------------------- SERVER lib --------------------------------- #

# --------------------------------- LOG lib --------------------------------- #
LOG_FILE="./log.txt"
rec_lock=0

# Reset
COLOR_OFF='\033[0m'       # Text Reset

# Regular Colors
COLOR_BLACK='\033[0;30m'        # Black
COLOR_RED='\033[0;31m'          # Red
COLOR_GREEN='\033[0;32m'        # Green
COLOR_YELLOW='\033[0;33m'       # Yellow
COLOR_BLUE='\033[0;34m'         # Blue
COLOR_PURPLE='\033[0;35m'       # Purple
COLOR_CYAN='\033[0;36m'         # Cyan
COLOR_WHITE='\033[0;37m'        # White

# Bold
BBlack='\033[1;30m'       # Black
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
BBlue='\033[1;34m'        # Blue
BPurple='\033[1;35m'      # Purple
BCyan='\033[1;36m'        # Cyan
BWhite='\033[1;37m'       # White

# Underline
UBlack='\033[4;30m'       # Black
URed='\033[4;31m'         # Red
UGreen='\033[4;32m'       # Green
UYellow='\033[4;33m'      # Yellow
UBlue='\033[4;34m'        # Blue
UPurple='\033[4;35m'      # Purple
UCyan='\033[4;36m'        # Cyan
UWhite='\033[4;37m'       # White

# Background
On_Black='\033[40m'       # Black
On_Red='\033[41m'         # Red
On_Green='\033[42m'       # Green
On_Yellow='\033[43m'      # Yellow
On_Blue='\033[44m'        # Blue
On_Purple='\033[45m'      # Purple
On_Cyan='\033[46m'        # Cyan
On_White='\033[47m'       # White

# High Intensity
IBlack='\033[0;90m'       # Black
IRed='\033[0;91m'         # Red
IGreen='\033[0;92m'       # Green
IYellow='\033[0;93m'      # Yellow
IBlue='\033[0;94m'        # Blue
IPurple='\033[0;95m'      # Purple
ICyan='\033[0;96m'        # Cyan
IWhite='\033[0;97m'       # White

# Bold High Intensity
BIBlack='\033[1;90m'      # Black
BIRed='\033[1;91m'        # Red
BIGreen='\033[1;92m'      # Green
BIYellow='\033[1;93m'     # Yellow
BIBlue='\033[1;94m'       # Blue
BIPurple='\033[1;95m'     # Purple
BICyan='\033[1;96m'       # Cyan
BIWhite='\033[1;97m'      # White

# High Intensity backgrounds
On_IBlack='\033[0;100m'   # Black
On_IRed='\033[0;101m'     # Red
On_IGreen='\033[0;102m'   # Green
On_IYellow='\033[0;103m'  # Yellow
On_IBlue='\033[0;104m'    # Blue
On_IPurple='\033[0;105m'  # Purple
On_ICyan='\033[0;106m'    # Cyan
On_IWhite='\033[0;107m'   # White

HDR_LOG_ERR="err"
HDR_LOG_WRN="wrn"
HDR_LOG_INF="inf"
HDR_LOG_DBG="dbg"

COLOR_PRINT() {
	local text=$1
	local text_color=$2

	if [[ "$text_color" == "BLACK" ]]; then
		echo -e ${COLOR_BLACK}${text}${COLOR_OFF}
	elif [[ "$text_color" == "RED" ]]; then
		echo -e ${COLOR_RED}${text}${COLOR_OFF}
	elif [[ "$text_color" == "GREEN" ]]; then
		echo -e ${COLOR_GREEN}${text}${COLOR_OFF}
	elif [[ "$text_color" == "YELLOW" ]]; then
		echo -e ${COLOR_YELLOW}${text}${COLOR_OFF}
	elif [[ "$text_color" == "BLUE" ]]; then
		echo -e ${COLOR_BLUE}${text}${COLOR_OFF}
	elif [[ "$text_color" == "PURPLE" ]]; then
		echo -e ${COLOR_PURPLE}${text}${COLOR_OFF}
	elif [[ "$text_color" == "CYAN" ]]; then
		echo -e ${COLOR_CYAN}${text}${COLOR_OFF}
	elif [[ "$text_color" == "WHITE" ]]; then
		echo -e ${COLOR_WHITE}${text}${COLOR_OFF}
	else
		echo $text
	fi
}

RECORD_INIT() {
	if [[ "$rec_lock" != 0 ]]; then
		COLOR_PRINT "<err> Log record already on going!" "RED"
		return
	fi

	local script_name=$1
	echo "Initial LOG..."
	echo ""
	local now="$(date +'%Y/%m/%d %H:%M:%S')"
	echo "[$now] <$HDR_LOG_INF> Start record log for script $script_name" > $LOG_FILE
	rec_lock=1
}

RECORD_EXIT() {
	if [[ "$rec_lock" != 1 ]]; then
		COLOR_PRINT "<err> Log record havn't init yet!" "RED"
		return
	fi

	local script_name=$1
	echo "Exit LOG..."
	echo ""
	local now="$(date +'%Y/%m/%d %H:%M:%S')"
	echo "[$now] <$HDR_LOG_INF> Stop record log for script $script_name" >> $LOG_FILE
	rec_lock=0
}

RECORD_LOG() {
	if [[ "$rec_lock" != 1 ]]; then
		COLOR_PRINT "<err> Log record havn't init yet!" "RED"
		return
	fi

	local hdr=$1
	local msg=$2
	local flag=$3
	local color

	if [[ "$hdr" == "$HDR_LOG_ERR" ]]; then
		hdr="<$hdr>"
		color="RED"
	elif [[ "$hdr" == "$HDR_LOG_WRN" ]]; then
		hdr="<$hdr>"
		color="YELLOW"
	elif [[ "$hdr" == "$HDR_LOG_DBG" ]]; then
		hdr="<$hdr>"
		color="PURPLE"
	elif [[ "$hdr" == "$HDR_LOG_INF" ]]; then
		hdr="<$hdr>"
		color="WHITE"
	fi

	local now="$(date +'%Y/%m/%d %H:%M:%S')"
	if [[ "$flag" == 0 ]]; then
		COLOR_PRINT "[$now] $hdr $msg" $color
	elif [[ "$flag" == 1 ]]; then
		echo "[$now] $hdr $msg" >> $LOG_FILE
	else
		COLOR_PRINT "[$now] $hdr $msg" $color
		echo "[$now] $hdr $msg" >> $LOG_FILE
	fi
}
# --------------------------------- LOG lib --------------------------------- #

# --------------------------------- PLATFORM lib --------------------------------- #
IPMI_I2C_MASTER_WR_RD(){
	bus=$1
	addr=$2
	rd_num=$3
	reg=$4
	data=$5
	IPMI_RAW_SEND "0x36" "0xf3" "$bus $addr $rd_num $reg $data"
}

SMBPBI_EVENT_CLR(){
	bus=$1
	addr=$2

	IPMI_RAW_SEND "0x36" "0xf3" "$bus $addr 0 $SMBPBI_REG_DATA 0x04 0x00 0x00 0x00 0x00"
	IPMI_RAW_SEND "0x36" "0xf3" "$bus $addr 0 $SMBPBI_REG_CS 0x04 $SMBPBI_OPCODE_INT_STAT 0x00 0x01 0x80"

	SMBPBI_STATUS_CHECK $bus $addr
	IFS=' ' read -r -a array <<< "$response_msg"
	if [[ "${array[4]}" == "1f" ]]; then
		return 0
	else
		return 1
	fi
}

SMBPBI_STATUS_CHECK(){
	bus=$1
	addr=$2
	IPMI_RAW_SEND "0x36" "0xf3" "$bus $addr 5 $SMBPBI_REG_CS"
	IFS=' ' read -r -a array <<< "$response_msg"
	if [[ "${array[4]}" == "1f" ]]; then
		COLOR_PRINT "OK" "GREEN"
		return 0
	elif [[ "${array[4]}" == "5f" ]]; then
		COLOR_PRINT "Try to clear pending event..." "YELLOW"
		SMBPBI_EVENT_CLR $bus $addr
	else
		COLOR_PRINT "Get unecpected status ${array[4]}" "RED"
		return 1
	fi
}

SMBPBI_FENCE_SWITCH(){
	op=$1
	if [ $op == "hmc" ]; then
		IPMI_I2C_MASTER_WR_RD $I2C_1 $FPGA_ADDR 0 $SMBPBI_REG_CS "0x04 $SMBPBI_OPCODE_FENCE 0x00 0x00 0x80"
		SMBPBI_STATUS_CHECK $I2C_1 $FPGA_ADDR
		return $?
	elif [ $op == "hostbmc" ]; then
		IPMI_I2C_MASTER_WR_RD $I2C_1 $FPGA_ADDR 0 $SMBPBI_REG_CS "0x04 $SMBPBI_OPCODE_FENCE 0x01 0x00 0x80"
		SMBPBI_STATUS_CHECK $I2C_1 $FPGA_ADDR
		return $?
	fi
}

SMBPBI_ACCESS(){
	bus=$1
	addr=$2
	opcode=$3
	arg1=$4
	arg2=$5
	data_wr=$6

	echo "[INF] Try to do smbpbi access"
	if [ ! -z $data_wr ]; then
		echo "Write data..."
		IPMI_I2C_MASTER_WR_RD $bus $addr 0 $SMBPBI_REG_DATA "0x04 $data_wr"
	fi

	echo "Write command..."
	IPMI_I2C_MASTER_WR_RD $bus $addr 0 $SMBPBI_REG_CS "0x04 $opcode $arg1 $arg2 0x80"

	echo "Read status..."
	SMBPBI_STATUS_CHECK $bus $addr
	if [ $? == 1 ]; then
		COLOR_PRINT "Write failed!" "RED"
		return
	fi

	echo "Read data..."
	IPMI_I2C_MASTER_WR_RD $bus $addr 5 $SMBPBI_REG_DATA
	COLOR_PRINT "---> $response_msg" "BLUE"
}

DIRECT_ACCESS(){
	bus=$1
	addr=$2
	rd_cnt=$3
	reg=$4

	echo "[INF] Try to do direct access"
	IPMI_I2C_MASTER_WR_RD "$bus" "$addr" "$rd_cnt" "$reg" ""
	COLOR_PRINT "---> $response_msg" "BLUE"
}

DEV_PICK(){
	key=$1
	if [ -z "$key" ]; then
		return 1
	elif [ $key == "0" ]; then
		device_addr=$FPGA_ADDR
	elif [ $key == "1" ]; then
		device_addr=$HMC_ADDR
	elif [ $key == "2" ]; then
		device_addr=$GPU1_ADDR
	elif [ $key == "3" ]; then
		device_addr=$GPU2_ADDR
	elif [ $key == "4" ]; then
		device_addr=$GPU3_ADDR
	elif [ $key == "5" ]; then
		device_addr=$GPU4_ADDR
	elif [ $key == "6" ]; then
		device_addr=$GPU5_ADDR
	elif [ $key == "7" ]; then
		device_addr=$GPU6_ADDR
	elif [ $key == "8" ]; then
		device_addr=$GPU7_ADDR
	elif [ $key == "9" ]; then
		device_addr=$GPU8_ADDR
	else
		echo "Invalid device id $key"
		HELP
		return 1
	fi
	
	return 0
}
# --------------------------------- PLATFORM lib --------------------------------- #

# --------------------------------- COMMON lib --------------------------------- #
APP_HEADER(){
	echo "==================================="
	echo "APP NAME: $APP_NAME"
	echo "APP VERSION: $APP_VERSION"
	echo "APP RELEASE DATE: $APP_DATE"
	echo "APP AUTHOR: $APP_AUTH"
	echo "==================================="
}

APP_HELP(){
	echo "Usage: $0 -m [mode] -b [bus] -d [device_id] -c [cmd_list] -w <wr_data> -r <rd_num> -H <server_ip> -U <user_name> -P <user_password>"
	echo "       [mode] 0:smbpbi(default)"
	echo "              1:direct"
	echo "       [bus] 0-base i2c bus"
	echo "       [device_id] 0:fpga"
	echo "                   1:hmc"
	echo "                   2:gpu1"
	echo "                   3:gpu2"
	echo "                   4:gpu3"
	echo "                   5:gpu4"
	echo "                   6:gpu5"
	echo "                   7:gpu6"
	echo "                   8:gpu7"
	echo "                   9:gpu8"
	echo "       [cmd_list] *mode=0: 'opcode + arg1 + arg2'"
	echo "                  *mode=1: register"
	echo "       <wr_data> *mode=0: 'write bytes list'"
	echo "       <rd_num> *mode=1: bytes to read $read_num(default)"
	echo "       <server_ip> $SERVER_IP(default)"
	echo "       <user_name> $USER_NAME(default)"
	echo "       <user_password> $USER_PWD(default)"
	echo ""
}

STAGE(){
	if [ $1 == "start" ]; then
		echo "[INF] Stop mctpd..."
		COLOR_PRINT "skip" "BLACK"
		echo "[INF] Disable sensor polling..."
		COLOR_PRINT "skip" "BLACK"
		echo "[INF] Try to switch fencing to HOST BMC..."
		SMBPBI_FENCE_SWITCH "hostbmc"
	elif [ $1 == "stop" ]; then
		echo "[INF] Try to switch fencing to HMC..."
		SMBPBI_FENCE_SWITCH "hmc"
		echo "[INF] Start sensor polling..."
		COLOR_PRINT "skip" "BLACK"
		echo "[INF] Start mctpd..."
		COLOR_PRINT "skip" "BLACK"
	fi
}
# --------------------------------- COMMON lib --------------------------------- #

APP_HEADER

SHORT=H:,U:,P:,m:,b:,d:,c:,r:,w:,h
LONG=ip:,user:,pwd:,mode:,bus:,device:,command:,read:,write:,help
OPTS=$(getopt -a -n weather --options $SHORT --longoptions $LONG -- "$@")

eval set -- "$OPTS"

MIN_CHECK_CNT=4
check_cnt=0
while :
do
  case "$1" in
  	-H | --ip )
		SERVER_IP="$2"
		shift 2
		;;
	-U | --user )
		USER_NAME="$2"
		shift 2
		;;
	-P | --pwd )
		USER_PWD="$2"
		shift 2
		;;
	-m | --mode )
		mode="$2"
		if [ $2 == "0" ]; then
			mode=$MODE_SMBPBI
			check_cnt=$((check_cnt+1))
		elif [ $2 == "1" ]; then
			mode=$MODE_DIRECT
			check_cnt=$((check_cnt+1))
		else
			COLOR_PRINT "Invalid mode $2" "RED"
		fi
		shift 2
		;;
	-b | --bus )
		i2c_bus="$2"
		check_cnt=$((check_cnt+1))
		shift 2
		;;
	-d | --device )
		DEV_PICK $2
		if [ $? == 0 ]; then
			check_cnt=$((check_cnt+1))
		fi
		shift 2
		;;
	-c | --command )
		command="$2"
		check_cnt=$((check_cnt+1))
		shift 2
		;;
	-r | --read )
		read_num="$2"
		shift 2
		;;
	-w | --write )
		wr_data="$2"
		shift 2
		;;
    -h | --help)
		APP_HELP
		exit 2
		;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      ;;
  esac
done

if [ $check_cnt -lt $MIN_CHECK_CNT ]; then
	COLOR_PRINT "Should have -m -b -d -c parameters" "YELLOW"
	echo ""
	APP_HELP
	exit 1
fi

SERVER_INIT $SERVER_IP $USER_NAME $USER_PWD
if [ $ipmi_init_success == 0 ]; then
	exit 1
fi

if [ $mode == $MODE_SMBPBI ]; then
	IFS=' ' read -r -a cmd_list <<< "$command"
	smbpbi_opcode="${cmd_list[0]}"
	smbpbi_arg1="${cmd_list[1]}"
	smbpbi_arg2="${cmd_list[2]}"

	COLOR_PRINT "Enter SMBPBI mode:" "YELLOW"
	echo "* bus:    $i2c_bus"
	echo "* addr:   $device_addr"
	echo "* opcode: $smbpbi_opcode"
	echo "* arg1:   $smbpbi_arg1"
	echo "* arg2:   $smbpbi_arg2"
	echo "* data:   $wr_data"
	echo ""
	STAGE "start"
	echo ""
	SMBPBI_ACCESS $i2c_bus $device_addr $smbpbi_opcode $smbpbi_arg1 $smbpbi_arg2 $wr_data
	echo ""
	STAGE "stop"
elif [ $mode == $MODE_DIRECT ]; then
	COLOR_PRINT "Enter DIRECT mode:" "YELLOW"
	echo "* bus:    $i2c_bus"
	echo "* addr:   $device_addr"
	echo "* cmd:    $command"
	echo "* rd_num  $read_num"
	echo ""
	DIRECT_ACCESS "$i2c_bus" "$device_addr" "$read_num" "$command" ""
fi
