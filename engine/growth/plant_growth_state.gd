class_name PlantGrowthState extends RefCounted

const DORMANT: StringName = &"dormant"
const ARMED: StringName = &"armed"
const GROWING: StringName = &"growing"
const PRESENT: StringName = &"present"

const VARIANT_MOSS: StringName = &"moss"
const VARIANT_GRASS: StringName = &"grass"
const VARIANT_BLOSSOM: StringName = &"blossom"
const VARIANT_FLOWER: StringName = &"flower"

const WARMTH_MIN: int = 600
const GROW_THRESHOLD_SECONDS: int = 300
const DECAY_THRESHOLD_SECONDS: int = 100

const PLANT_COMFORT_STRENGTH: int = 100
const PLANT_ADVERT_RADIUS_PX: int = 8  # 1 slot-height
