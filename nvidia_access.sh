#!/bin/bash

APP_NAME="NVIDIA DEVICE ACCESS TOOL"
APP_VERSION="1.2.0"
APP_DATE="2023/11/13"
APP_AUTH="Mouchen"

NVIDIA_CFG_FILE="./nvidia_cfg"

MODE_SMBPBI="smbpbi"
MODE_DIRECT="direct"

mode=$MODE_SMBPBI
i2c_bus="9"
device_addr="0"
device_name="none"
access_cmd="0x06 0x52"

bus_cfg_mode=1 #dufault bus need modified
pre_post_task_mode=1 #default need to switch fencing gate between HMC

command=""
read_num=1
wr_data=""

DBG_EN=0

# --------------------------------- SERVER lib --------------------------------- #
server_ip=""
user_name=""
user_pwd=""

IPMI_NETFN_SENSOR=0x04
IPMI_CMD_GET_SENSOR_READING=0x2d
IPMI_NETFN_APP=0x06
IPMI_CMD_GET_DEVICE_ID=0x01
IPMI_NETFN_STORAGE=0x0A

SERVER_CFG_FILE="./server_cfg"
REDFISH_SURF_FILE="./redfish_surf"

ipmi_cmd_prefix=""
ipmi_raw_cmd_prefix=""
ipmi_init_success=0
redfish_cmd_prefix=""
redfish_http_prefix=""
redfish_cmd_suffix="|python -m json.tool | GREP_COLOR='01;32' egrep -i --color=always '@odata|'"

KEYWORD_SERVER_IP="SERVER_IP"
KEYWORD_USER_NAME="USER_NAME"
KEYWORD_USER_PWD="USER_PWD"

LOAD_CFG(){
	if [[ ! -f "$SERVER_CFG_FILE" ]]; then
		echo "$SERVER_CFG_FILE not exists."
		return 1
	fi

	#~~~~~~~~~~~~ Format EX ~~~~~~~~~~~~~
	#SERVER_IP=10.10.11.78
	#USER_NAME=admin
	#USER_PWD=admin
	#~~~~~~~~~~~~ Format EX ~~~~~~~~~~~~~
	if [ -z "$server_ip" ]; then
		key_str=`cat $SERVER_CFG_FILE |grep $KEYWORD_SERVER_IP`
		IFS='=' read -r -a array <<< "$key_str"
		server_ip="${array[1]}"
	fi
	if [ -z "$user_name" ]; then
		key_str=`cat $SERVER_CFG_FILE |grep $KEYWORD_USER_NAME`
		IFS='=' read -r -a array <<< "$key_str"
		user_name="${array[1]}"
	fi
	if [ -z "$user_pwd" ]; then
		key_str=`cat $SERVER_CFG_FILE |grep $KEYWORD_USER_PWD`
		IFS='=' read -r -a array <<< "$key_str"
		user_pwd="${array[1]}"
	fi

	return 0
}

SERVER_INIT(){
	server_ip=$1
	user_name=$2
	user_pwd=$3

	if [ -z "$server_ip" ] || [ -z "$user_name" ] || [ -z "$user_pwd" ]; then
		LOAD_CFG
		if [ $? == 1 ]; then
			ipmi_init_success=0
			return
		fi
	fi

	echo "{Server info}"
	echo "* ip:       $server_ip"
	echo "* user:     $user_name"
	echo "* password: $user_pwd"
	echo ""

	ipmi_cmd_prefix="ipmitool -H $server_ip -U $user_name -P $user_pwd -I lanplus"
	ipmi_raw_cmd_prefix="$ipmi_cmd_prefix raw"

	redfish_http_prefix="https://$server_ip"
    redfish_cmd_prefix="curl -s -k -u $user_name:$user_pwd"

	#Pre-test
	ipmi_init_success=1
	IPMI_RAW_SEND $IPMI_NETFN_APP $IPMI_CMD_GET_DEVICE_ID
	if [ $? == 1 ]; then
		echo "[ERR] Failed to init server!"
		ipmi_init_success=0
		return
	fi

	#Update server config
	echo "$KEYWORD_SERVER_IP=$server_ip" > $SERVER_CFG_FILE
	echo "$KEYWORD_USER_NAME=$user_name" >> $SERVER_CFG_FILE
	echo "$KEYWORD_USER_PWD=$user_pwd" >> $SERVER_CFG_FILE
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

REDFISH_FILTER_PRINT(){
	# must using json format output
	redfish_output=$1
	base_path=$2
	keyword=$3

	COLOR_PRINT "[ $keyword ]" "YELLOW"
	while read -r line; do
	    if [[ $line == *$keyword* ]]; then
			IFS=': '
			read -a strarr <<< "$line"
			AF=""
			foo=${strarr[1]#'"'}
			foo=${foo%','}
			foo=${foo%'"'}

			if [[ $foo != *$base_path* ]]; then
				continue
			fi
			
			if [ $foo == "$base_path" ]; then
				continue
			fi

			if [ $foo == "/$base_path" ]; then
				continue
			fi

			echo "  $foo"
		fi
	done < <(printf %s "$redfish_output")
}

REDFISH_SEND(){
	op=$1

	#command list if op=0
	#extend command list if op>0
	cmd_list=$2
	ext_cmd=$3

	#only works for POST mode
	data=""

	if [ $op == 0 ]; then
		action_cmd="-X GET"
	elif [ $op == 1 ]; then
		action_cmd="-H 'Content-Type: application/json' -X POST"
		data=$4
		data="-d '$data'"
	else
		action_cmd=""
	fi

	COLOR_PRINT "[input]" "BLUE"
	echo "$redfish_cmd_prefix $action_cmd $redfish_http_prefix/$cmd_list $data $ext_cmd"
	
	# add /HMC filter
	hmc_filter=`echo $cmd_list |sed "s/hmc//1"`

	# highlight command line
	hi_light="| GREP_COLOR='01;31' egrep -i --color=always '$hmc_filter|'"
	cmd_out="$redfish_cmd_prefix $action_cmd $redfish_http_prefix/$cmd_list $data $redfish_cmd_suffix $hi_light $ext_cmd"
	#echo $cmd_out

	COLOR_PRINT "[output]" "BLUE"
	eval $cmd_out
	eval result=\$\("$redfish_cmd_prefix $action_cmd $redfish_http_prefix/$cmd_list $data |python -m json.tool"\)

	echo -e "\n\n"

	REDFISH_FILTER_PRINT "$result" "$hmc_filter" "@odata.id"
	REDFISH_FILTER_PRINT "$result" "$hmc_filter" "target"
}

REDFISH_SURF(){
	local CMD=$1
	local layer=$2

	echo "$redfish_cmd_prefix -X GET $redfish_http_prefix$CMD |python -m json.tool"
	b=`$redfish_cmd_prefix -X GET $redfish_http_prefix$CMD |python -m json.tool`
	#echo $b |python -m json.tool

	while read -r line; do
	    if [[ $line == *"@odata.id"* ]]; then
			IFS=': '
			read -a strarr <<< "$line"
			AF=""
	  		echo ${strarr[1]}
			foo=${strarr[1]#'"'}
			foo=${foo%','}
			foo=${foo%'"'}

			if [[ $foo != *$CMD* ]]; then
				continue
			fi
			
			if [ $foo == $CMD ]; then
				continue
			fi
			echo "$layer: $foo"
			echo "$layer: $foo" >> $REDFISH_SURF_FILE
			REDFISH_SURF "$foo" $((layer+1))
		fi
	done < <(printf %s "$b")
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
	IPMI_RAW_SEND $access_cmd "$bus $addr $rd_num $reg $data"
}

LOAD_NV_CFG(){
	key=$1
	nv_bus1=$2
	nv_bus2=$3

	if [ $key == 0 ];then
		I2C_1="0x01" #for FPGA/GPU
		I2C_2="0x02" #for FPGA/HMC/NVSWITCH
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

	elif [ $key == 1 ]; then
		if [[ ! -f "$NVIDIA_CFG_FILE" ]]; then
			echo "$NVIDIA_CFG_FILE not exists."
			return 1
		fi

		KEYWORD_NV_I2C1="I2C_1"
		KEYWORD_NV_I2C2="I2C_2"
		KEYWORD_NV_ADDR_GPU1="GPU1_ADDR"
		KEYWORD_NV_ADDR_GPU2="GPU2_ADDR"
		KEYWORD_NV_ADDR_GPU3="GPU3_ADDR"
		KEYWORD_NV_ADDR_GPU4="GPU4_ADDR"
		KEYWORD_NV_ADDR_GPU5="GPU5_ADDR"
		KEYWORD_NV_ADDR_GPU6="GPU6_ADDR"
		KEYWORD_NV_ADDR_GPU7="GPU7_ADDR"
		KEYWORD_NV_ADDR_GPU8="GPU8_ADDR"
		KEYWORD_NV_ADDR_FPGA="FPGA_ADDR"
		KEYWORD_NV_ADDR_HMC="HMC_ADDR"
		KEYWORD_NV_REG_CS="SMBPBI_REG_CS"
		KEYWORD_NV_REG_DATA="SMBPBI_REG_DATA"
		KEYWORD_NV_SMBPBI_OP_CAP="SMBPBI_OPCODE_CAP"
		KEYWORD_NV_SMBPBI_OP_STEMP="SMBPBI_OPCODE_S_TEMP"
		KEYWORD_NV_SMBPBI_OP_ETEMP="SMBPBI_OPCODE_E_TEMP"
		KEYWORD_NV_SMBPBI_OP_INITSTAT="SMBPBI_OPCODE_INT_STAT"
		KEYWORD_NV_SMBPBI_OP_FENCE="SMBPBI_OPCODE_FENCE"

		#~~~~~~~~~~~~ Format EX ~~~~~~~~~~~~~
		#I2C_1=0x01
		#I2C_2=0x02
		#GPU1_ADDR=0x88
		#...
		#FPGA_ADDR=0xc0
		#HMC_ADDR=0xa8
		#SMBPBI_OPCODE_CAP=0x01
		#...
		#~~~~~~~~~~~~ Format EX ~~~~~~~~~~~~~
		
		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_I2C1`
		IFS='=' read -r -a array <<< "$key_str"
		I2C_1="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_I2C2`
		IFS='=' read -r -a array <<< "$key_str"
		I2C_2="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU1`
		IFS='=' read -r -a array <<< "$key_str"
		GPU1_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU2`
		IFS='=' read -r -a array <<< "$key_str"
		GPU2_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU3`
		IFS='=' read -r -a array <<< "$key_str"
		GPU3_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU4`
		IFS='=' read -r -a array <<< "$key_str"
		GPU4_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU5`
		IFS='=' read -r -a array <<< "$key_str"
		GPU5_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU6`
		IFS='=' read -r -a array <<< "$key_str"
		GPU6_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU7`
		IFS='=' read -r -a array <<< "$key_str"
		GPU7_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_GPU8`
		IFS='=' read -r -a array <<< "$key_str"
		GPU8_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_FPGA`
		IFS='=' read -r -a array <<< "$key_str"
		FPGA_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_ADDR_HMC`
		IFS='=' read -r -a array <<< "$key_str"
		HMC_ADDR="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_REG_CS`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_REG_CS="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_REG_DATA`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_REG_DATA="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_SMBPBI_OP_CAP`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_OPCODE_CAP="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_SMBPBI_OP_STEMP`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_OPCODE_S_TEMP="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_SMBPBI_OP_ETEMP`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_OPCODE_E_TEMP="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_SMBPBI_OP_INITSTAT`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_OPCODE_INT_STAT="${array[1]}"

		key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_SMBPBI_OP_FENCE`
		IFS='=' read -r -a array <<< "$key_str"
		SMBPBI_OPCODE_FENCE="${array[1]}"
	
	elif [ $key == 2 ]; then
		if [ ! -z "$nv_bus1" ]; then
			I2C_1=$nv_bus1
			replace_str="$KEYWORD_NV_I2C1=$nv_bus1"
			key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_I2C1`
			sed -i "s/$key_str/$replace_str/" $NVIDIA_CFG_FILE
			COLOR_PRINT "Nvidia config $KEYWORD_NV_I2C1 has been update!" "BLACK"
		fi
		if [ ! -z "$nv_bus2" ]; then
			I2C_2=$nv_bus2
			replace_str="$KEYWORD_NV_I2C2=$nv_bus2"
			key_str=`cat $NVIDIA_CFG_FILE |grep $KEYWORD_NV_I2C2`
			sed -i "s/$key_str/$replace_str/" $NVIDIA_CFG_FILE
			COLOR_PRINT "Nvidia config $KEYWORD_NV_I2C2 has been update!" "BLACK"
		fi
	else
		echo "Invalid key $key while load nvidia config"
		return 1
	fi

	return 0
}

SMBPBI_STATUS_PARSING(){
	val=$1
	if [ -z "$val" ]; then
		COLOR_PRINT "Get empty smbpbi status" "RED"
		return
	elif [ $val == "00" ]; then
		COLOR_PRINT "Get smbpbi status $val(NULL)" "RED"
	elif [ $val == "01" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_REQUEST)" "RED"
	elif [ $val == "02" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_OPCODE)" "RED"
	elif [ $val == "03" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_ARG1)" "RED"
	elif [ $val == "04" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_ARG2)" "RED"
	elif [ $val == "05" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_DATA)" "RED"
	elif [ $val == "06" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_MISC)" "RED"
	elif [ $val == "07" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_I2C_ACCESS)" "RED"
	elif [ $val == "08" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_NOT_SUPPORTED)" "RED"
	elif [ $val == "09" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_NOT_AVAILABLE)" "RED"
	elif [ $val == "0A" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_BUSY)" "RED"
	elif [ $val == "0B" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_AGAIN)" "RED"
	elif [ $val == "0C" ]; then
		COLOR_PRINT "Get smbpbi status $val(ERR_SENSOR_DATA)" "RED"
	elif [ $val == "1C" ]; then
		COLOR_PRINT "Get smbpbi status $val(ACCEPTED)" "RED"
	elif [ $val == "1D" ]; then
		COLOR_PRINT "Get smbpbi status $val(INACTIVE)" "RED"
	elif [ $val == "1E" ]; then
		COLOR_PRINT "Get smbpbi status $val(READY)" "RED"
	elif [ $val == "1F" ]; then
		#SUCCESS
		return
	else
		COLOR_PRINT "Get unexpected smbpbi status $val" "RED"
	fi
}

SMBPBI_EVENT_CLR(){
	bus=$1
	addr=$2

	IPMI_RAW_SEND $access_cmd "$bus $addr 0 $SMBPBI_REG_DATA 0x04 0x00 0x00 0x00 0x00"
	IPMI_RAW_SEND $access_cmd "$bus $addr 0 $SMBPBI_REG_CS 0x04 $SMBPBI_OPCODE_INT_STAT 0x00 0x01 0x80"

	SMBPBI_STATUS_CHECK $bus $addr $SMBPBI_OPCODE_INT_STAT "0x00" "0x01"
	if [ $? == 1 ]; then
		return 1
	fi

	IFS=' ' read -r -a array <<< "$response_msg"
	if [[ "${array[4]}" == "1f" ]]; then
		return 0
	else
		COLOR_PRINT "Failed to clear event flag!" "RED"
		return 1
	fi
}

SMBPBI_STATUS_CHECK(){
	bus=$1
	addr=$2
	local opcode=$3
	local arg1=$4
	local arg2=$5

	opcode=`echo "$opcode" | tr '[:upper:]' '[:lower:]'`
	arg1=`echo "$arg1" | tr '[:upper:]' '[:lower:]'`
	arg2=`echo "$arg2" | tr '[:upper:]' '[:lower:]'`

	IPMI_RAW_SEND $access_cmd "$bus $addr 5 $SMBPBI_REG_CS"

	if [ $? == 1 ]; then
		return 1
	fi

	if [ $DBG_EN == 1 ];then
		COLOR_PRINT "[dbg] status check with return $response_msg" "PURPLE"
	fi

	IFS=' ' read -r -a array <<< "$response_msg"

	if [ "${array[0]}" != "04" ]; then
		COLOR_PRINT "Invalid read length byte" "RED"
		return 1
	fi

	if [[ "${array[4]}" == "1f" ]]; then
		if [ "0x${array[1]}" == $opcode ] && [ "0x${array[2]}" == $arg1 ] && [ "0x${array[3]}" == $arg2 ]; then
			COLOR_PRINT "OK" "GREEN"
			return 0
		fi
		COLOR_PRINT "Status wrire command(0x${array[1]},0x${array[2]},0x${array[3]}) is not match with input command($opcode,$arg1,$arg2)" "RED"
		return 1
	elif [[ "${array[4]}" == "5f" ]]; then
		COLOR_PRINT "Try to clear pending event..." "YELLOW"
		SMBPBI_EVENT_CLR $bus $addr
		if [ $? == 1 ]; then
			return 1
		fi
	else
		SMBPBI_STATUS_PARSING "${array[4]}"
		return 1
	fi
}

SMBPBI_FENCE_SWITCH(){
	op=$1
	if [ $op == "hmc" ]; then
		IPMI_I2C_MASTER_WR_RD $I2C_1 $FPGA_ADDR 0 $SMBPBI_REG_CS "0x04 $SMBPBI_OPCODE_FENCE 0x00 0x00 0x80"
		SMBPBI_STATUS_CHECK $I2C_1 $FPGA_ADDR $SMBPBI_OPCODE_FENCE "0x00" "0x00"
		return $?
	elif [ $op == "hostbmc" ]; then
		IPMI_I2C_MASTER_WR_RD $I2C_1 $FPGA_ADDR 0 $SMBPBI_REG_CS "0x04 $SMBPBI_OPCODE_FENCE 0x01 0x00 0x80"
		SMBPBI_STATUS_CHECK $I2C_1 $FPGA_ADDR $SMBPBI_OPCODE_FENCE "0x01" "0x00"
		return $?
	fi
}

SMBPBI_ACCESS(){
	bus=$1
	addr=$2
	local opcode=$3
	local arg1=$4
	local arg2=$5
	data_wr=$6

	echo "[INF] Try to do smbpbi access"
	if [ ! -z $data_wr ]; then
		echo "Write data..."
		IPMI_I2C_MASTER_WR_RD $bus $addr 0 $SMBPBI_REG_DATA "0x04 $data_wr"
	fi

	echo "Write command..."
	IPMI_I2C_MASTER_WR_RD $bus $addr 0 $SMBPBI_REG_CS "0x04 $opcode $arg1 $arg2 0x80"

	echo "Read status..."
	SMBPBI_STATUS_CHECK $bus $addr $opcode $arg1 $arg2
	if [ $? == 1 ]; then
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
		device_name="FPGA"
		device_addr=$FPGA_ADDR
	elif [ $key == "1" ]; then
		device_name="HMC"
		device_addr=$HMC_ADDR
	elif [ $key == "2" ]; then
		device_name="GPU1"
		device_addr=$GPU1_ADDR
	elif [ $key == "3" ]; then
		device_name="GPU2"
		device_addr=$GPU2_ADDR
	elif [ $key == "4" ]; then
		device_name="GPU3"
		device_addr=$GPU3_ADDR
	elif [ $key == "5" ]; then
		device_name="GPU4"
		device_addr=$GPU4_ADDR
	elif [ $key == "6" ]; then
		device_name="GPU5"
		device_addr=$GPU5_ADDR
	elif [ $key == "7" ]; then
		device_name="GPU6"
		device_addr=$GPU6_ADDR
	elif [ $key == "8" ]; then
		device_name="GPU7"
		device_addr=$GPU7_ADDR
	elif [ $key == "9" ]; then
		device_name="GPU8"
		device_addr=$GPU8_ADDR
	else
		echo "Invalid device id $key"
		HELP
		return 1
	fi
	
	return 0
}

BUS_PICK(){
	key=$1
	if [ -z "$key" ]; then
		return 1
	elif [ $key == "0" ]; then
		i2c_bus=$I2C_1
	elif [ $key == "1" ]; then
		i2c_bus=$I2C_2
	else
		echo "Invalid bus id $key"
		return 1
	fi

	return 0
}

CMD_PICK(){
	#access_cmd format should be "<netfn_hex> <cmd_hex> <(optional)iana>"
	#bus_cfg_mode 0:no need to modify
	#             1:2*bus+1
	key=$1
	if [ -z "$key" ]; then
		return 1
	elif [ $key == "0" ]; then
		access_cmd="0x06 0x52"
		bus_cfg_mode=1
	elif [ $key == "1" ]; then
		access_cmd="0x36 0xf3"
		bus_cfg_mode=0
	else
		echo "Invalid cmd id $key, using default standard command"
		access_cmd="0x06 0x52"
		bus_cfg_mode=1
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
	LOAD_CFG
	echo "Usage: $0 -m [mode] -b [bus_id] -d [device_id] -c [cmd_list] -w <wr_data> -r <rd_num> -B '<bus1> <bus2>' -C <cmd_pick> -H <server_ip> -U <user_name> -P <user_password>"
	echo "       -m --mode (must)"
	echo "          [mode] 0"
	echo "                    smbpbi mode"
	echo "                 1"
	echo "                    direct mode"
	echo ""
	echo "       -b --busid (must)"
	echo "          [bus_id] 0"
	echo "                      BUS1($I2C_1), can config by -B"
	echo "                   1"
	echo "                      BUS2($I2C_2), can config by -B"
	echo ""
	echo "       -d --device (must)"
	echo "          [device_id] 0"
	echo "                         fpga ($FPGA_ADDR)"
	echo "                      1"
	echo "                         hmc ($HMC_ADDR)"
	echo "                      2"
	echo "                         gpu1 ($GPU1_ADDR)"
	echo "                      3"
	echo "                         gpu2 ($GPU2_ADDR)"
	echo "                      4"
	echo "                         gpu3 ($GPU3_ADDR)"
	echo "                      5"
	echo "                         gpu4 ($GPU4_ADDR)"
	echo "                      6"
	echo "                         gpu5 ($GPU5_ADDR)"
	echo "                      7"
	echo "                         gpu6 ($GPU6_ADDR)"
	echo "                      8"
	echo "                         gpu7 ($GPU7_ADDR)"
	echo "                      9"
	echo "                         gpu8 ($GPU8_ADDR)"
	echo ""
	echo "       -c --command (must)"
	echo "          [cmd_list] 'opcode + arg1 + arg2'"
	echo "                        While mode=0, smbpbi input command"
	echo "                     register"
	echo "                        While mode=1, register with 1 byte"
	echo ""
	echo "       -w --write (optional)"
	echo "          <wr_data> 'write bytes list'"
	echo "                       While mode=0, smbpbi input data list"
	echo ""
	echo "       -r --read (optional)"
	echo "          <rd_num> $read_num(default)"
	echo "                      While mode=1, bytes to read"
	echo ""
	echo "       -B --write (optional)"
	echo "          <bus1> $I2C_1(default)"
	echo "                    FPGA/GPU(0-base i2c bus)"
	echo "          <bus2> $I2C_2(default)"
	echo "                    FPGA/HMC(0-base i2c bus)"
	echo ""
	echo "       -C --cp (optional)"
	echo "          <cmd_pick> 0(default)"
	echo "                        Using standard master write read command NF:0x06 CMD:0x52"
	echo "                     1"
	echo "                        Using oem master write read command NF:0x36 CMD:0xf3"
	echo ""
	echo "       -H --ip (first time)"
	echo "          <server_ip> $server_ip(default)"
	echo ""
	echo "       -U --user (first time)"
	echo "          <user_name> $user_name(default)"
	echo ""
	echo "       -P --pwd (first time)"
	echo "          <user_password> $user_pwd(default)"
	echo ""
	echo "       -f --force (optional)"
	echo "          Skip pre-task and post-task"
	echo ""
	echo "       -v --debug (optional)"
	echo "          Enable debug print"
	echo ""
	echo "       -h --help (optional)"
	echo "          Get help"
	echo ""
}

STAGE(){
	key=$1
	action=$2

	if [ $key == 0 ]; then
		if [ $action == "start" ]; then
			COLOR_PRINT "[INF] Skip pre-task" "BLACK"
		elif [ $action == "stop" ]; then
			COLOR_PRINT "[INF] Skip post-task" "BLACK"
		else
			echo "[WRN] Invalid action $action..."
		fi
	elif [ $key == 1 ]; then
		if [ $action == "start" ]; then
			echo "[INF] Stop mctpd..."
			COLOR_PRINT "skip" "BLACK"
			echo "[INF] Disable sensor polling..."
			COLOR_PRINT "skip" "BLACK"
			echo "[INF] Try to switch fencing to HOST BMC..."
			SMBPBI_FENCE_SWITCH "hostbmc"
		elif [ $action == "stop" ]; then
			echo "[INF] Try to switch fencing to HMC..."
			SMBPBI_FENCE_SWITCH "hmc"
			echo "[INF] Start sensor polling..."
			COLOR_PRINT "skip" "BLACK"
			echo "[INF] Start mctpd..."
			COLOR_PRINT "skip" "BLACK"
		else
			echo "[WRN] Invalid action $action..."
		fi
	else
		echo "[WRN] Invalid task mode $key..."
	fi
}
# --------------------------------- COMMON lib --------------------------------- #

APP_HEADER

LOAD_NV_CFG 1
if [ $? == 1 ];then
	COLOR_PRINT "Something goes wrong while loading nvidia config with file '$NVIDIA_CFG_FILE', use DEFAULT config" "YELLOW"
	LOAD_NV_CFG 0
fi

SHORT=H:,U:,P:,C:,B:,m:,b:,d:,c:,r:,w:,f,v,h
LONG=ip:,user:,pwd:,cp:,buscfg:,mode:,busid:,device:,command:,read:,write:,force,debug,help
OPTS=$(getopt -a -n weather --options $SHORT --longoptions $LONG -- "$@")

eval set -- "$OPTS"

bus_id="0"
given_i2c1=""
given_i2c2=""

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
	-C | --cp )
		CMD_PICK $2
		shift 2
		;;
	-B | --buscfg )
		i2c_list="$2"
		i2c_list=($i2c_list)
		given_i2c1=${i2c_list[0]}
		given_i2c2=${i2c_list[1]}
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
	-b | --busid )
		bus_id=$2
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
	-f | --force )
		pre_post_task_mode=0
		shift 1
		;;
	-v | --debug )
		DBG_EN=1
		shift 1
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

# Update nvidia config
LOAD_NV_CFG 2 $given_i2c1 $given_i2c2

if [ $check_cnt -lt $MIN_CHECK_CNT ]; then
	COLOR_PRINT "Should have -m -b -d -c parameters" "YELLOW"
	echo ""
	APP_HELP
	exit 1
fi

BUS_PICK $bus_id
if [ $? == 1 ]; then
	echo ""
	APP_HELP
	exit 1
fi

if [ $bus_cfg_mode == 1 ];then
	i2c_bus="$((i2c_bus*2+1))"
fi

SERVER_INIT $SERVER_IP $USER_NAME $USER_PWD
if [ $ipmi_init_success == 0 ]; then
	exit 1
fi

COLOR_PRINT "APP cfg:" "YELLOW"
if [ $pre_post_task_mode == 0 ]; then
	echo "* taskmode:  force"
else
	echo "* taskmode:  fencing"
fi
echo ""

COLOR_PRINT "NVIDIA OOB cfg:" "YELLOW"
echo "* bus1:   $I2C_1 (FPGA/GPU)"
echo "* bus2:   $I2C_2 (FPGA/HMC)"
echo ""

if [ $mode == $MODE_SMBPBI ]; then
	IFS=' ' read -r -a cmd_list <<< "$command"
	smbpbi_opcode="${cmd_list[0]}"
	smbpbi_arg1="${cmd_list[1]}"
	smbpbi_arg2="${cmd_list[2]}"

	COLOR_PRINT "Enter SMBPBI mode:" "YELLOW"
	echo "* device: $device_name"
	echo "* bus:    $i2c_bus"
	echo "* addr:   $device_addr"
	echo "* cmd:    $access_cmd"
	echo "* opcode: $smbpbi_opcode"
	echo "* arg1:   $smbpbi_arg1"
	echo "* arg2:   $smbpbi_arg2"
	echo "* data:   $wr_data"
	echo ""
	STAGE $pre_post_task_mode "start"
	echo ""
	SMBPBI_ACCESS $i2c_bus $device_addr $smbpbi_opcode $smbpbi_arg1 $smbpbi_arg2 $wr_data
	echo ""
	STAGE $pre_post_task_mode "stop"
elif [ $mode == $MODE_DIRECT ]; then
	COLOR_PRINT "Enter DIRECT mode:" "YELLOW"
	echo "* device:  $device_name"
	echo "* bus:     $i2c_bus"
	echo "* addr:    $device_addr"
	echo "* cmd:     $access_cmd"
	echo "* ofst:    $command"
	echo "* rd_num   $read_num"
	echo ""
	DIRECT_ACCESS "$i2c_bus" "$device_addr" "$read_num" "$command" ""
fi
