-- Quest tags QuestieDB cannot give on its own. The rest is read from QuestieDB at load
-- (Data.lua): seasonal = a holiday quest sort, war effort = the AQ war effort sort (-365),
-- dungeon = the quest's zone is a dungeon or raid.
-- Quest IDs are facts about the game (quest pages on Wowhead, the client's own quest data).
local _, ns = ...

ns.Extras = {}

-- Holiday quests QuestieDB files under "Special" (-284) or under a city.
ns.Extras.seasonal = { -- 16 quests
    [171]=true, [172]=true, [558]=true, [910]=true, [911]=true, [915]=true, [925]=true, [1468]=true, [1479]=true, [1558]=true, [1687]=true, [1800]=true,
    [4822]=true, [5502]=true, [7905]=true, [7926]=true,
}

-- AQ war effort quests QuestieDB files under their zone (Silithus, Ahn'Qiraj).
ns.Extras.warEffort = { -- 10 quests
    [8780]=true, [8781]=true, [8782]=true, [8783]=true, [8784]=true, [8785]=true, [8786]=true, [8787]=true, [8788]=true, [8789]=true,
}

-- Dungeon and raid quests given outside the instance (city, class trainer, attunement
-- chains), so their zone is not a dungeon.
ns.Extras.instance = { -- 148 quests
    -- 88 where an objective (creature, object, or an item no vendor sells) exists only
    -- in a dungeon or raid, per QuestieDB.
    [1654]=true, [1740]=true, [1951]=true, [1956]=true, [4143]=true, [6821]=true, [6822]=true, [6824]=true, [7463]=true, [7581]=true, [7629]=true, [7631]=true,
    [7635]=true, [7642]=true, [7647]=true, [7668]=true, [7786]=true, [8232]=true, [8236]=true, [8253]=true, [8257]=true, [8258]=true, [8905]=true, [8906]=true,
    [8907]=true, [8908]=true, [8909]=true, [8911]=true, [8912]=true, [8913]=true, [8914]=true, [8915]=true, [8916]=true, [8918]=true, [8919]=true, [8920]=true,
    [8926]=true, [8927]=true, [8931]=true, [8932]=true, [8933]=true, [8934]=true, [8935]=true, [8936]=true, [8937]=true, [8938]=true, [8939]=true, [8940]=true,
    [8941]=true, [8942]=true, [8943]=true, [8944]=true, [8951]=true, [8952]=true, [8953]=true, [8954]=true, [8955]=true, [8956]=true, [8957]=true, [8958]=true,
    [8959]=true, [8961]=true, [8999]=true, [9000]=true, [9001]=true, [9002]=true, [9003]=true, [9004]=true, [9005]=true, [9006]=true, [9007]=true, [9008]=true,
    [9009]=true, [9010]=true, [9011]=true, [9012]=true, [9013]=true, [9014]=true, [9016]=true, [9017]=true, [9018]=true, [9019]=true, [9020]=true, [9021]=true,
    [9022]=true, [9023]=true, [9053]=true, [9251]=true,
    -- 60 more, from quest pages and community lists.
    [1442]=true, [1653]=true, [2769]=true, [3906]=true, [4148]=true, [4262]=true, [5103]=true, [5281]=true, [5305]=true, [5306]=true, [5307]=true, [5522]=true,
    [5526]=true, [5721]=true, [6187]=true, [6402]=true, [6403]=true, [6501]=true, [6582]=true, [6583]=true, [6584]=true, [6585]=true, [7634]=true, [7643]=true,
    [7649]=true, [7650]=true, [7651]=true, [7666]=true, [7737]=true, [8182]=true, [8315]=true, [8316]=true, [8351]=true, [8352]=true, [8364]=true, [8376]=true,
    [8377]=true, [8378]=true, [8379]=true, [8380]=true, [8381]=true, [8382]=true, [8413]=true, [8418]=true, [8422]=true, [8425]=true, [8585]=true, [8620]=true,
    [8729]=true, [8735]=true, [8736]=true, [8868]=true, [8910]=true, [8917]=true, [8994]=true, [9250]=true, [9257]=true, [9269]=true, [9270]=true, [9271]=true,
}
