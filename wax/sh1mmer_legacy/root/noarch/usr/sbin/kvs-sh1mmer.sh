 #!/bin/bash
echo "NOTICE: KVS is for UNENROLLED CHROMEBOOKS ONLY!"
sleep 3
echo "Please Enter Target kernver (0-3)"
      read -rep "> " kernver
      case $kernver in
        "0")
          echo "Setting kernver 0"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  0 0 0 0  0 0 0  e8
          sleep 2
          echo "Finished writing kernver $kernver!"
          echo "Press ENTER to return to main menu.."
          read -r
          ;;
        "1")
          echo "Setting kernver 1"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  1 0 1 0  0 0 0  55
          echo "Finished writing kernver $kernver!"
          echo "Press ENTER to return to main menu.."
          read -r
          ;;
        "2")
          echo "Setting kernver 2"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  2 0 1 0  0 0 0  33
          echo "Finished writing kernver $kernver!"
          echo "Press ENTER to return to main menu.."
          read -r
          ;;
        "3")
          echo "Setting kernver 3"
          initctl stop trunksd
          tpmc write 0x1008 02  4c 57 52 47  3 0 1 0  0 0 0  EC
          echo "Finished writing kernver $kernver!"
          echo "Press ENTER to return to main menu.."
          read -r
          ;;
        *)
          echo "Invalid kernver. Please check your input."
          ;;
      esac ;;
