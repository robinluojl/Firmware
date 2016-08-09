#!/bin/bash

rc_script=$1
debugger=$2
program=$3
model=$4
build_path=$5
curr_dir=`pwd`

echo SITL ARGS
echo rc_script: $rc_script
echo debugger: $debugger
echo program: $program
echo model: $model
echo build_path: $build_path

mkdir -p $build_path/rootfs/fs/microsd
mkdir -p $build_path/rootfs/eeprom

if [ "$model" == "" ] || [ "$model" == "none" ]
then
	echo "empty model, setting iris as default"
	model="iris"
fi

if [ "$#" -lt 5 ]
then
	echo usage: sitl_run.sh rc_script debugger program model build_path
	echo ""
	exit 1
fi

# kill process names that might stil
# be running from last time
pkill gazebo
pkill px4
jmavsim_pid=`jps | grep Simulator | cut -d" " -f1`
if [ -n "$jmavsim_pid" ]
then
	kill $jmavsim_pid
fi

set -e

cd $build_path/..
cp Tools/posix_lldbinit $build_path/rootfs/.lldbinit
cp Tools/posix.gdbinit $build_path/rootfs/.gdbinit

SIM_PID=0

if [ "$program" == "jmavsim" ] && [ ! -n "$no_sim" ]
then
	cd Tools/jMAVSim
	ant create_run_jar copy_res
	cd out/production
	java -Djava.ext.dirs= -jar jmavsim_run.jar -udp 127.0.0.1:14560 &
	SIM_PID=`echo $!`
	cd ../..
elif [ "$program" == "gazebo" ] && [ ! -n "$no_sim" ]
then
	if [ -x "$(command -v gazebo)" ]
	then
		# Set the plugin path so Gazebo finds our model and sim
		export GAZEBO_PLUGIN_PATH=$curr_dir/build_gazebo:${GAZEBO_PLUGIN_PATH}
		# Set the model path so Gazebo finds the airframes
		export GAZEBO_MODEL_PATH=${GAZEBO_MODEL_PATH}:$curr_dir/Tools/sitl_gazebo/models
		# The next line would disable online model lookup, can be commented in, in case of unstable behaviour.
		# export GAZEBO_MODEL_DATABASE_URI=""
		export SITL_GAZEBO_PATH=$curr_dir/Tools/sitl_gazebo
		make --no-print-directory gazebo_build

		gzserver --verbose $curr_dir/Tools/sitl_gazebo/worlds/${model}.world &
		SIM_PID=`echo $!`

		if [[ -n "$HEADLESS" ]]; then
			echo "not running gazebo gui"
		else
			gzclient --verbose &
			GUI_PID=`echo $!`
		fi
	else
		echo "You need to have gazebo simulator installed!"
		exit 1
	fi
elif [ "$program" == "replay" ] && [ ! -n "$no_sim" ]
then
	echo "Replaying logfile: $logfile"
	# This is not a simulator, but a log file to replay

	# Check if we need to creat a param file to allow user to change parameters
	if ! [ -f "${build_path}/rootfs/replay_params.txt" ]
		then
		touch ${build_path}/rootfs/replay_params.txt
	fi
fi

cd $build_path/rootfs

if [ "$logfile" != "" ]
then
	cp $logfile rootfs/replay.px4log
fi

# Do not exit on failure now from here on because we want the complete cleanup
set +e

# Prepend to path to prioritize PX4 commands over potentially already
# installed PX4 commands.
export PATH="$build_path/bin":$PATH

export SIM_MODEL=${model}
export SIM_PROGRAM=${program}

# Start Java simulator
if [ "$debugger" == "lldb" ]
then
	lldb -- px4 etc/init/${rc_script}
elif [ "$debugger" == "gdb" ]
then
	gdb --args px4 etc/init/${rc_script}
elif [ "$debugger" == "ddd" ]
then
	ddd --debugger gdb --args px4 etc/init${rc_script}
elif [ "$debugger" == "valgrind" ]
then
	valgrind px4 etc/init/${rc_script}
else
	px4 etc/init/${rc_script}
fi

if [ "$program" == "jmavsim" ]
then
	kill -9 $SIM_PID
elif [ "$program" == "gazebo" ]
then
	kill -9 $SIM_PID
	if [[ ! -n "$HEADLESS" ]]; then
		kill -9 $GUI_PID
	fi
fi
