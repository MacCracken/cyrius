interface Builder { build(): this; }
class B { chain(): this { return this; } }
class P { is(): this is P { return; } }
