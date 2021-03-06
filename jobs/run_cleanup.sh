source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt
source /home/jenkins-slave/tools/keystonerc_admin
source /usr/local/src/osbrick-ci/jobs/library.sh

set +e

if [ "$IS_DEBUG_JOB" != "yes" ]
    then
        jen_date=$(date +%d/%m/%Y-%H:%M:%S)
        echo "Detaching and cleaning Hyper-V node 1"
        teardown_hyperv $hyperv01 $WIN_USER $WIN_PASS
        echo "$jen_date;$ZUUL_PROJECT;$ZUUL_BRANCH;$ZUUL_CHANGE;$ZUUL_PATCHSET;$JOB_TYPE;$hyperv01;FREE" >> /home/jenkins-slave/hypervnodes.log

        echo "Releasing devstack floating IP"
        nova remove-floating-ip "$VMID" "$FLOATING_IP"
        
        echo "Removing devstack VM"
        nova delete "$VMID"
        /usr/local/src/osbrick-ci/vlan_allocation.py -r $VMID
        
        echo "Deleting devstack floating IP"
        nova floating-ip-delete "$FLOATING_IP"
        rm -f /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt
fi

set -e
