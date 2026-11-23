extends Resource
## "When <material> is hit by something tagged <tag>": scale the damage and maybe
## trigger an effect. A hit's tags are its action (pierce / slash / blunt) and its
## element (fire / frost / shock). Every matching rule applies (mults multiply).
## material "*" matches any material.

@export var material := "*"
@export var tag := ""
@export var damage_mult := 1.0
@export_enum("none", "ignite", "extinguish") var effect := "none"
