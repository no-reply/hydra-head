# Allows you to use CanCan to control access to Models
class Ability
  include Hydra::Ability
  include Hydra::PolicyAwareAbility
end
