# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This seeds file creates sample data using the new data model:
# - Products as first-class entities
# - Specs with JSONB requirements (no separate Requirement table)
# - SpecImplState and SpecImplRef instead of RequirementStatus and CodeReference
# - Implementations belong to Products, not Specs

Acai.Seeds.run()
