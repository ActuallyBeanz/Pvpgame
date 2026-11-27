extends Resource
## "When a hit of <element> lands on someone who has <status>": change the damage, maybe use the
## status up, maybe give another one. Every matching rule applies (in list order).
## Example: Wet + shock = x1.75 damage, Wet used up, "ELECTROCUTED!".

@export var status := ""                   ## the status the target already has
@export var element := ""                  ## the incoming hit's element
@export var damage_mult := 1.0
@export var bonus_damage := 0.0
@export var consume_status := false        ## the target loses <status>
@export var apply_status := ""             ## and gets this one instead ("" = none)
@export var apply_duration := -1.0         ## -1 = that status's default
@export var block_element_status := false  ## the element's own status isn't applied (fire on Wet: no Burning)
@export var popup := ""                    ## floating text over the target ("ELECTROCUTED!")
@export var popup_color := Color.WHITE
