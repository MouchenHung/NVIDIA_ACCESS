# NVIDIA_ACCESS
Nvidia devices access tool which including smbpbi/direct access.

### Purpose:
    Tools that used to send smbpbi/direct command to NVIDIA devices via i2c.

### Latest rlease:
    * nvidia_access: v1.2.0 - 2023/11/13

### Version:
**[nvidia_access]**
- 1.2.0 - Modify and Increase more ARGs to meet different platforms - 2023/11/13
  - Feature:
    - Support Bus config(-B) Command pick(-C) and debug print(-v) and force access(-f) ARGS.
    - Command pick currently support NF:0x06 Cmd:0x52 and NF:0x36 Cmd:0xf3.
    - Modify arg -b from bus number to bus id.
    - Support server config storage ipmi_cfg and nvidia config storage nvidia_cfg.
    - Update IPMI library.
    - Support HGX8 and CG1 types of modules.
  - Bug:
  	- none

- 1.1.0 - First commit - 2023/09/21
  - Feature:
    - Support devices including GPU(8 index), FPGA, HMC.
    - Support direct mode and smbpbi mode.
    - Support fencing switch between BMC and HMC.
  - Bug:
  	- none

### Requirement:
- OS
  - Linux: support
- Enviroment
  - Ubuntu 18.04

### Usage
  - **STEP0-0. Create server config file(only do once)**\
  Create server config file by adding command.\
  ./nvidia_access.sh ... -H < server_ip > -U < user_name > -P < user_password >

  - **STEP0-1. Modify nvidia I2C_1 and I2C_2 from config file(only do once)**\
  Modify nvidia config file by adding command.\
  ./nvidia_access.sh ... -B '< I2C_1 > < I2C_2 >'
  
  - **STEP1. Send commands**\
```
**HELP**
mouchen@mouchen-System-Product-Name:~/Documents/BMC/common/tool/NVIDIA_TOOL/NVIDIA_ACCESS$ ./nvidia_access.sh -h
===================================
APP NAME: NVIDIA DEVICE ACCESS TOOL
APP VERSION: 1.2.0
APP RELEASE DATE: 2023/11/13
APP AUTHOR: Mouchen
===================================
Usage: ./nvidia_access.sh -m [mode] -b [bus_id] -d [device_id] -c [cmd_list] -w <wr_data> -r <rd_num> -B '<bus1> <bus2>' -C <cmd_pick> -H <server_ip> -U <user_name> -P <user_password>
       -m --mode (must)
          [mode] 0
                    smbpbi mode
                 1
                    direct mode

       -b --busid (must)
          [bus_id] 0
                      BUS1(0x9), can config by -B
                   1
                      BUS2(0xA), can config by -B

       -d --device (must)
          [device_id] 0
                         fpga (0xc0)
                      1
                         hmc (0xa8)
                      2
                         gpu1 (0x88)
                      3
                         gpu2 (0x8a)
                      4
                         gpu3 (0x8c)
                      5
                         gpu4 (0x8e)
                      6
                         gpu5 (0x98)
                      7
                         gpu6 (0x9a)
                      8
                         gpu7 (0x9c)
                      9
                         gpu8 (0x9e)

       -c --command (must)
          [cmd_list] 'opcode + arg1 + arg2'
                        While mode=0, smbpbi input command
                     register
                        While mode=1, register with 1 byte

       -w --write (optional)
          <wr_data> 'write bytes list'
                       While mode=0, smbpbi input data list

       -r --read (optional)
          <rd_num> 1(default)
                      While mode=1, bytes to read

       -B --write (optional)
          <bus1> 0x9(default)
                    FPGA/GPU(0-base i2c bus)
          <bus2> 0xA(default)
                    FPGA/HMC(0-base i2c bus)

       -C --cp (optional)
          <cmd_pick> 0(default)
                        Using standard master write read command NF:0x06 CMD:0x52
                     1
                        Using oem master write read command NF:0x36 CMD:0xf3

       -H --ip (first time)
          <server_ip> 10.10.11.78(default)

       -U --user (first time)
          <user_name> admin(default)

       -P --pwd (first time)
          <user_password> admin(default)

       -f --force (optional)
          Skip pre-task and post-task

       -v --debug (optional)
          Enable debug print

       -h --help (optional)
          Get help

**SMBPBI example**
mouchen@mouchen-System-Product-Name:~/Documents/BMC/common/tool/NVIDIA_TOOL/NVIDIA_ACCESS$ ./nvidia_access.sh -m 0 -b 0 -d 6 -c '0x02 0x00 0x00' -H 10.10.11.78 -U admin -P admin -C 1 -B '0x9 0xA'
===================================
APP NAME: NVIDIA DEVICE ACCESS TOOL
APP VERSION: 1.2.0
APP RELEASE DATE: 2023/11/13
APP AUTHOR: Mouchen
===================================
Nvidia config I2C_1 has been update!
Nvidia config I2C_2 has been update!
{Server info}
* ip:       10.10.11.78
* user:     admin
* password: admin

APP cfg:
* taskmode:  fencing

NVIDIA OOB cfg:
* bus1:   0x9 (FPGA/GPU)
* bus2:   0xA (FPGA/HMC)

Enter SMBPBI mode:
* device: GPU5
* bus:    0x9
* addr:   0x98
* cmd:    0x36 0xf3
* opcode: 0x02
* arg1:   0x00
* arg2:   0x00
* data:   

[INF] Stop mctpd...
skip
[INF] Disable sensor polling...
skip
[INF] Try to switch fencing to HOST BMC...
OK

[INF] Try to do smbpbi access
Write command...
Read status...
OK
Read data...
---> 04 00 22 00 00

[INF] Try to switch fencing to HMC...
OK
[INF] Start sensor polling...
skip
[INF] Start mctpd...
skip

**DIRECT example**
mouchen@mouchen-System-Product-Name:~/Documents/BMC/common/tool/NVIDIA_TOOL/NVIDIA_ACCESS$ ./nvidia_access.sh -f -m 1 -b 0 -d 3 -c 0x63 -H 10.10.11.78 -U admin -P admin -C 1
===================================
APP NAME: NVIDIA DEVICE ACCESS TOOL
APP VERSION: 1.2.0
APP RELEASE DATE: 2023/10/09
APP AUTHOR: Mouchen
===================================
{Server info}
* ip:       10.10.11.78
* user:     admin
* password: admin

APP cfg:
* taskmode:  force

NVIDIA OOB cfg:
* bus1:   0x9 (FPGA/GPU)
* bus2:   0xA (FPGA/HMC)

Enter DIRECT mode:
* device:  GPU2
* bus:     0x9
* addr:    0x8a
* cmd:     0x36 0xf3
* ofst:    0x63
* rd_num   1

[INF] Try to do direct access
---> 10

```

### Note
- Do not delete **server_cfg**, otherwise STEP0-0 is required once.
- Do not delete **nvidia_cfg**, otherwise this APP will out of function.
