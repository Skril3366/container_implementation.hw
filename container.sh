#!/bin/bash

FILE_SIZE=10000
IMG_FILE="container.img"
MOUNT_POINT="/mnt/container"

ROOT_FS_FILE_NAME="rootfs.tar"

CGROUP_NAME="container"

COMMAND="python3 /benchmark.py"

create_rootfs_image_if_not_exists() {
	if [ ! -f "$ROOT_FS_FILE_NAME" ]; then
		local tag="container_fs_builder"
		docker build ./ -t $tag
		local image_id=$(docker images --format="{{.Repository}} {{.ID}}" | grep $tag | awk '{print $2}')
		local container_id=$(docker create "$image_id")
		docker export "$container_id" -o $ROOT_FS_FILE_NAME
		docker container rm "$container_id"
		docker image rm "$image_id"
	fi
}

create_filesystem() {
	echo "Starting to create img file..."
	dd if=/dev/zero of=$IMG_FILE bs=1M count=$FILE_SIZE &>/dev/null

	echo "Creating loop device..."
	LOOP_DEVICE=$(sudo losetup -fP --show $IMG_FILE)

	echo "Creating filesystem..."
	sudo mkfs.ext4 "$LOOP_DEVICE" &>/dev/null

	echo "Mounting file system..."
	sudo mkdir -p $MOUNT_POINT
	sudo mount "$LOOP_DEVICE" "$MOUNT_POINT"

	echo "Downloading root filesystem..."
	create_rootfs_image_if_not_exists

	echo "Extracting root filesystem..."
	sudo tar -xf $ROOT_FS_FILE_NAME -C $MOUNT_POINT
}

delete_filesystem() {
	echo "Cleaning up..."
	sudo umount "$MOUNT_POINT"
	sudo losetup -D "$LOOP_DEVICE"
	rm "$IMG_FILE"
}

run_isolated_shell() {
	local cg_arg="cpu,memory:$CGROUP_NAME"
	cgcreate -g "$cg_arg"

	cgexec -g "$cg_arg" \
		unshare --net --fork --mount --pid \
		chroot $MOUNT_POINT /bin/bash -c "$COMMAND" || true
}

exit_if_not_sudo() {
	if [ "$(id -u)" != "0" ]; then
		echo "This script must be run with sudo or as root" 1>&2
		exit 1
	fi
}

prepare_environment() {
  cp ./benchmark.py $MOUNT_POINT
}

close_environment() {
  cp $MOUNT_POINT/report.md ./
}

main() {
	exit_if_not_sudo
	create_filesystem
  prepare_environment
	echo
	run_isolated_shell
  close_environment
	delete_filesystem
}

main
