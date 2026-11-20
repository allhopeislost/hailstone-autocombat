local whitelist = require('lib.whitelist')
local settings = require('lib.settings')
local targeting = require('lib.targeting')
local engine = require('lib.engine')
local fake = require('fake')

case('whitelist: normalized exact names and respawn suffixes', function()
  local w = {}
  check(whitelist.add(w, 'Qeynos', '  a_fire_beetle005  '), 'add with trim')
  check(whitelist.contains(w, 'qeynos', 'A Fire Beetle'), 'underscores, case and suffix ignored')
  check(whitelist.contains(w, 'QEYNOS', 'a_fire_beetle007'), 'another spawn of the mob')
  check(not whitelist.contains(w, 'qeynos', 'a fire beetle scout'), 'not a substring match')
  check(not whitelist.contains(w, 'freeport', 'a fire beetle'), 'zone isolation')
  check(not whitelist.add(w, 'qeynos', 'a fire beetle'), 'normalized duplicates rejected')
  check(whitelist.add(w, 'freeport', 'A Fire Beetle'), 'same NPC in another zone')
  eq(#w.qeynos, 1, 'one unique Qeynos entry')
  check(whitelist.remove(w, 'qeynos', 'a fire beetle'), 'remove by normal name')
  check(not w.qeynos, 'empty zone removed')
  check(whitelist.contains(w, 'freeport', 'a fire beetle'), 'other zone untouched')
  check(not whitelist.remove(w, 'qeynos', 'a fire beetle'), 'cannot remove twice')
end)

case('whitelist: invalid inputs and oversized lists are rejected', function()
  local w = {}
  for _, invalid in ipairs({'', '  ', 'Name\nOther', string.rep('a', 121)}) do
    check(not whitelist.add(w, 'qeynos', invalid), 'invalid name refused')
  end
  check(not whitelist.add(w, '../qeynos', 'a mob'), 'bad zone refused')
  check(not whitelist.add(w, nil, 'a mob'), 'nil zone refused')
  check(not whitelist.add(w, 'qeynos', '000'), 'empty canonical name refused')
  local loaded = settings.repair({ targeting = { whitelist = { qeynos = { ' Mob ', 'mob', '', 4,
    'something\nelse', 'Another' }, ['bad zone'] = { 'Other' }, freeport = 'wrong' } } })
  eq(#loaded.targeting.whitelist.qeynos, 2, 'only two valid unique NPCs retained')
  eq(loaded.targeting.whitelist.qeynos[1], 'Mob', 'trimmed name saved')
  check(loaded.targeting.whitelist['bad zone'] == nil, 'invalid zones discarded')
  check(loaded.targeting.whitelist.freeport == nil, 'non-list discarded')
  local list = { qeynos = {} }
  for i = 1, whitelist.MAX_NAMES do check(whitelist.add(list, 'qeynos', 'Mob' .. i .. 'X'), 'within cap ' .. i) end
  check(not whitelist.add(list, 'qeynos', 'OverLimit'), 'zone capacity enforced')
end)

case('whitelist: survives settings save repair per character and zone', function()
  local s = settings.defaults()
  check(whitelist.add(s.targeting.whitelist, 'qeynos', 'a beetle'), 'first zone')
  check(whitelist.add(s.targeting.whitelist, 'freportw', 'a decaying skeleton'), 'second zone')
  s = settings.repair(s)
  check(whitelist.contains(s.targeting.whitelist, 'qeynos', 'a beetle'), 'first zone saved')
  check(whitelist.contains(s.targeting.whitelist, 'freportw', 'a decaying skeleton'), 'second zone saved')
  check(not whitelist.contains(s.targeting.whitelist, 'freportw', 'a beetle'), 'zones independent')
  local other = settings.defaults()
  check(not whitelist.contains(other.targeting.whitelist, 'qeynos', 'a beetle'), 'other character defaults empty')
end)

case('whitelist: overrides all Hunter filters, but never players or pets', function()
  local s = settings.repair({ targeting = { whitelist = { qeynos = { 'Innkeep Harold' } },
    min_level = 40, max_level = 50, named = false, ignore = { 'innkeep' },
    cons = { grey = false }, mob_cons = { Ally = false } } })
  local t = s.targeting
  local inn = fake.spawn({ id = 2, name = 'Innkeep_Harold000', level = 3, con = 'grey',
    class_id = 41, named = true, faction_con = 'Ally', x = 900, y = 0, players_near = true })
  check(targeting.allowed(inn, t, 'qeynos'), 'everything overridden')
  check(not targeting.allowed(inn, t, 'freportw'), 'only in current zone')
  local h = settings.defaults().hunter
  local list = targeting.hunt_candidates({ inn }, t, h, { 0, 0, 0 }, {}, true, false, 'qeynos')
  eq(#list, 1, 'bypasses radius, camp leash, Z and player proximity')
  check(list[1].whitelisted, 'candidate marked to skip faction lookup')
  inn.owned = true
  check(not targeting.allowed(inn, t, 'qeynos'), 'does not target a pet')
  inn.owned = false
  inn.npc = false
  check(not targeting.allowed(inn, t, 'qeynos'), 'does not target a player')
  inn.npc = true
  inn.hp = 0
  eq(#targeting.hunt_candidates({ inn }, t, h, { 0, 0, 0 }, {}, true, false, 'qeynos'), 1,
    'zero percent is not dead')
  inn.dead = true
  eq(#targeting.hunt_candidates({ inn }, t, h, { 0, 0, 0 }, {}, true, false, 'qeynos'), 0,
    'dead entries excluded')
end)

case('whitelist: takes candidate priority even over the closer usual targets', function()
  local s = settings.repair({ targeting = { whitelist = { qeynos = { 'Named Target' } } } })
  local normal = fake.spawn({ id = 1, name = 'a rat', x = 10, y = 0 })
  local chosen = fake.spawn({ id = 2, name = 'Named_Target003', x = 1500, y = 0 })
  local list = targeting.hunt_candidates({ normal, chosen }, s.targeting, s.hunter,
    { 0, 0, 0 }, {}, false, false, 'qeynos')
  eq(#list, 2, 'whitelist beyond radius still in pool')
  eq(list[1].id, 2, 'whitelist sorted first')
  eq(list[2].id, 1, 'normal candidate second')
end)

case('whitelist: still chosen outside the radius with the whole-zone search off', function()
  local s = settings.repair({ mode = 'hunter', hunter = { wide_search = false },
    targeting = { whitelist = { testzone = { 'Named Target' } } } })
  local chosen = fake.spawn({ id = 2, name = 'Named_Target003', x = 1500, y = 0, distance = 1500 })
  local e, io = engine.new(), fake.io()
  engine.start(e, io)
  engine.tick(e, fake.world({ hunt = { chosen }, spawns = { chosen }, paths = { [2] = 1600 } }), s, io)
  eq(e.hunt and e.hunt.id, 2, 'whitelisted beyond the radius')
end)

case('whitelist: all faction standings off still hunts only whitelisted mobs, without /consider', function()
  local s = settings.repair({ mode = 'hunter', targeting = {
    mob_cons = { Scowling = false, Threateningly = false, Dubious = false, Apprehensive = false,
      Indifferent = false, Amiably = false, Kindly = false, Warmly = false, Ally = false },
    whitelist = { testzone = { 'Innkeep Harold' } },
  } })
  local inn = fake.spawn({ id = 20, name = 'Innkeep_Harold000', x = 100, distance = 100, class_id = 41,
    faction_con = 'Ally' })
  local normal = fake.spawn({ id = 21, name = 'a bat', x = 20, distance = 20 })
  local e, io = engine.new(), fake.io()
  engine.start(e, io)
  local w = fake.world({ hunt = { normal, inn }, spawns = { normal, inn }, paths = { [20] = 1500, [21] = 20 } })
  engine.tick(e, w, s, io)
  eq(e.hunt and e.hunt.id, 20, 'whitelisted NPC chosen despite all filters and max path')
  eq(io.considered, nil, 'no faction query for whitelisted NPC')
  engine.tick(e, w, s, io)
  check(io.has('/nav id 20 distance=10'), 'continues navigating to whitelisted innkeeper')
  eq(io.considered, nil, 'still no faction query')
  local s2 = settings.repair({ mode = 'hunter', targeting = { mob_cons = s.targeting.mob_cons } })
  local e2, io2 = engine.new(), fake.io()
  engine.start(e2, io2)
  engine.tick(e2, w, s2, io2)
  eq(e2.status, 'Mob Con: no faction standings selected', 'without whitelist no mobs hunted')
end)
