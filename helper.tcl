namespace eval tpm {
    nx::Class create Helper {
        :property colors
        :method init {} {
            # Named colors exposed by the tpm UI. Each entry maps a logical
            # name used across the client to a zesty style specification
            # (foreground color plus optional style flags).
            set :colors {
                red_bold {fg red bold 1}
                red      {fg red}
                green    {fg green}
                yellow   {fg yellow bold 1}
                blue     {fg blue bold 1}
                magenta  {fg magenta bold 1}
                cyan     {fg cyan}
                reset    {}
            }
            next
        }

        :public method style {color} {
            # Translate a tpm logical color name into a zesty style list.
            # Unknown names yield an empty style, i.e. plain output.
            if {$color ne "" && [dict exists ${:colors} $color]} {
                return [dict get ${:colors} $color]
            }
            return {}
        }

        :public method cputs {args} {
            set color ""
            set text ""

            if {[llength $args] == 1} {
                set text [lindex $args 0]
            } elseif {[llength $args] == 2} {
                set color [lindex $args 0]
                set text  [lindex $args 1]
            } else {
                error "Usage: cputs ?color? text"
            }

            zesty::echo $text -style [:style $color]
        }

        :public method cputs_multi {segments} {
            # Render a flat {color text color text ...} list as a single
            # styled line. Segments whose color is unknown are emitted
            # unstyled, matching the previous escape-code behaviour.
            set rendered ""
            foreach {color text} $segments {
                set style [:style $color]
                if {[llength $style]} {
                    append rendered [zesty::parseStyle $text $style]
                } else {
                    append rendered $text
                }
            }
            zesty::echo $rendered -noreset
        }
		
		:method show_title {title} {
			zesty::echo [zesty::rule -title "name \"<s fg=green>$title</s>\" align left" -style {fg cyan bold 1}]
		}
		
		:method show_error {errMsg {separator 1}} {
			zesty::echo [zesty::rule -title {name "<s fg=red>Error:</s>" align left} -style {fg cyan bold 1}]
			zesty::echo "  --> <s fg=red>$errMsg</s>"
			if {$separator} {:show_separator}
		}
		
		:method show_separator {} {
			zesty::echo [zesty::rule -style {fg cyan bold 1}]
		}
    }
}
