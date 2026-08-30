nomad_banner() {
    clear
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)

    if [ "$term_width" -ge 105 ]; then
        cat << 'BIGBANNER'
NNNNNNNN        NNNNNNNN                                                                      d::::::d
N:::::::N       N::::::N                                                                      d::::::d
N::::::::N      N::::::N                                                                      d::::::d
N:::::::::N     N::::::N                                                                      d:::::d 
N::::::::::N    N::::::N   ooooooooooo      mmmmmmm    mmmmmmm     aaaaaaaaaaaaa      ddddddddd:::::d 
N:::::::::::N   N::::::N oo:::::::::::oo  mm:::::::m  m:::::::mm   a::::::::::::a   dd::::::::::::::d 
N:::::::N::::N  N::::::No:::::::::::::::om::::::::::mm::::::::::m  aaaaaaaaa:::::a d::::::::::::::::d 
N::::::N N::::N N::::::No:::::ooooo:::::om::::::::::::::::::::::m           a::::ad:::::::ddddd:::::d 
N::::::N  N::::N:::::::No::::o     o::::om:::::mmm::::::mmm:::::m    aaaaaaa:::::ad::::::d    d:::::d 
N::::::N   N:::::::::::No::::o     o::::om::::m   m::::m   m::::m  aa::::::::::::ad:::::d     d:::::d 
N::::::N    N::::::::::No::::o     o::::om::::m   m::::m   m::::m a::::aaaa::::::ad:::::d     d:::::d 
N::::::N     N:::::::::No::::o     o::::om::::m   m::::m   m::::ma::::a    a:::::ad:::::d     d:::::d 
N::::::N      N::::::::No:::::ooooo:::::om::::m   m::::m   m::::ma::::a    a:::::ad::::::ddddd::::::dd
N::::::N       N:::::::No:::::::::::::::om::::m   m::::m   m::::ma:::::aaaa::::::a d:::::::::::::::::d
N::::::N        N::::::N oo:::::::::::oo m::::m   m::::m   m::::m a::::::::::aa:::a d:::::::::ddd::::d
NNNNNNNN         NNNNNNN   ooooooooooo   mmmmmm   mmmmmm   mmmmmm  aaaaaaaaaa  aaaa  ddddddddd   ddddd
BIGBANNER
    else
        cat << 'SMALLBANNER'
█   █   ███   █   █   ███   ████ 
██  █  █   █  ██ ██  █   █  █   █
█ █ █  █   █  █ █ █  █████  █   █
█  ██  █   █  █   █  █   █  █   █
█   █   ███   █   █  █   █  ████ 
SMALLBANNER
    fi

    echo "Backup & Restore everywhere, everytime."
    echo
}
