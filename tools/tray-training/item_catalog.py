"""트레이 소지품 목록 (gen_items.py 용): (그룹, 품목, 변형, 긴 변 cm[, 변형당 장수]).

학습은 1클래스 "item" 이라 그룹은 분석·크기용이다. 상표 이름은 넣지 않는다.
"""

ITEMS = [
    # 휴대폰
    ("phone", "smartphone lying face down", ["black", "white", "silver", "blue", "pink", "green", "titanium gray"], (14, 17)),
    ("phone", "smartphone lying face up with a dark screen", ["black bezel", "thin bezel", "with a clear case", "with a colorful case"], (14, 17)),
    ("phone", "smartphone in a protective case, back side", ["leather case", "silicone case", "clear case", "card wallet case", "patterned case"], (14, 17)),
    ("phone", "folded flip smartphone (clamshell foldable)", ["lavender", "black", "cream", "mint", "yellow"], (8, 9)),
    ("phone", "folded book-style foldable smartphone", ["black", "silver", "navy"], (15, 16)),
    # 지갑
    ("wallet", "bifold leather wallet", ["black", "brown", "tan", "navy", "burgundy", "gray"], (9, 12)),
    ("wallet", "slim card holder wallet", ["black leather", "brown leather", "beige", "red", "metal"], (8, 11)),
    ("wallet", "long zip wallet", ["black", "pink", "brown monogram-free", "white"], (17, 20)),
    ("wallet", "small coin purse", ["leather", "fabric", "clasp-style", "zipper"], (8, 12)),
    # 열쇠
    ("key", "car smart key fob", ["black plastic", "black with chrome trim", "silver and black", "folding key"], (6, 9)),
    ("key", "car key fob on a keyring with one house key", ["black", "silver"], (8, 12)),
    ("key", "metal house keys on a ring", ["two keys", "three keys", "keys with a small charm", "brass keys"], (6, 10)),
    ("key", "RFID door key tag (plastic fob) on a keyring", ["blue", "black", "white", "red"], (4, 7)),
    ("key", "keychain with a small plush charm and keys", ["bear charm", "character charm", "leather tassel"], (9, 13)),
    # 카드
    ("card", "employee ID badge in a clear plastic holder with its lanyard loosely coiled beside it", ["blue lanyard", "black lanyard", "red lanyard", "gray lanyard"], (12, 18)),
    ("card", "employee ID badge on a retractable badge reel clip", ["black reel", "white reel"], (9, 12)),
    ("card", "plastic ID card with a photo, blurred text", ["white", "light blue", "horizontal", "vertical"], (8.5, 8.6)),
    ("card", "credit card", ["black", "gold", "silver", "blue", "white"], (8.5, 8.6)),
    ("card", "transit card", ["blue", "colorful", "with a cartoon print", "white"], (8.5, 8.6)),
    # 이어폰
    ("audio", "wireless earbuds charging case, closed", ["glossy white pill-shaped", "white rounded square", "matte black", "lavender", "graphite", "white with lid open"], (5, 7)),
    ("audio", "pair of white wireless earbuds with stems", ["lying side by side", "one earbud"], (3, 4.5)),
    ("audio", "coiled wired earphones with a cable", ["white", "black"], (6, 12)),
    ("audio", "folded over-ear headphones", ["black", "white", "beige"], (16, 20)),
    # 시계
    ("watch", "analog wristwatch with a metal bracelet", ["silver", "gold", "black", "two-tone"], (17, 22)),
    ("watch", "analog wristwatch with a leather strap", ["brown", "black", "tan"], (20, 24)),
    ("watch", "square smartwatch with a sport band", ["black", "white", "pink", "midnight blue", "starlight"], (18, 23)),
    ("watch", "round smartwatch with a silicone band", ["black", "silver", "gold"], (18, 23)),
    ("watch", "slim fitness tracker band", ["black", "pink", "gray"], (18, 22)),
    # 안경
    ("eyewear", "folded eyeglasses", ["black frames", "tortoiseshell frames", "thin metal frames", "clear frames", "round gold frames"], (13, 15)),
    ("eyewear", "folded sunglasses", ["black", "brown gradient", "aviator gold"], (13, 15)),
    ("eyewear", "eyeglass case", ["black hard shell", "brown leather", "fabric pouch"], (15, 17)),
    # 화장·위생
    ("toiletry", "lip balm stick", ["white", "blue", "pink", "green", "clear tube", "with cap off"], (6, 7.5)),
    ("toiletry", "small round lip balm tin", ["silver", "colorful printed"], (4, 5)),
    ("toiletry", "lipstick", ["gold case", "black case", "red case", "cap off"], (7, 8.5)),
    ("toiletry", "hand cream tube", ["white", "pastel pink", "lavender", "green", "beige", "metallic"], (8, 14)),
    ("toiletry", "sunscreen tube", ["white and orange", "blue", "white"], (10, 15)),
    ("toiletry", "small hand sanitizer bottle", ["clear with blue gel", "white", "pink"], (7, 11)),
    ("toiletry", "cushion compact makeup case", ["white", "black", "pink", "silver", "open"], (7, 9)),
    ("toiletry", "small perfume bottle", ["clear glass", "pink glass", "travel spray"], (7, 11)),
    ("toiletry", "small eye drop bottle", ["white", "blue cap"], (4, 6)),
    ("toiletry", "pill organizer box", ["clear", "colorful", "round"], (6, 12)),
    ("toiletry", "compact pocket mirror", ["silver round", "pink round", "folding square"], (6, 8)),
    ("toiletry", "small comb", ["black plastic", "wooden", "pink"], (10, 15)),
    ("toiletry", "hair tie and hair clip", ["black", "colorful scrunchie", "claw clip"], (4, 9)),
    ("toiletry", "nail clipper", ["silver", "black"], (6, 8)),
    # 휴지
    ("tissue", "pocket tissue pack", ["white", "printed", "blue", "pink"], (10, 12)),
    ("tissue", "small wet wipes pack", ["white and blue", "green", "pink"], (12, 16)),
    ("tissue", "folded disposable face mask", ["white KF94", "black KF94", "white surgical"], (11, 18)),
    # 충전·전자
    ("charger", "USB-C wall charger brick with folding plug", ["white", "black", "small cube"], (4, 7)),
    ("charger", "wall charger with round european plug pins", ["white", "black"], (6, 8)),
    ("charger", "coiled USB cable", ["white", "black", "braided red", "braided gray"], (8, 14)),
    ("charger", "portable power bank", ["white", "black", "silver", "pastel", "with a cable plugged in"], (9, 15)),
    ("charger", "magnetic wireless power bank", ["white", "purple", "blue"], (9, 11)),
    ("charger", "USB flash drive", ["silver metal", "black plastic", "colorful", "on a keyring"], (3, 6)),
    ("charger", "round wireless charging pad", ["white", "black"], (8, 11)),
    ("charger", "wireless computer mouse", ["black", "white", "gray"], (9, 12)),
    ("charger", "small USB card reader adapter", ["silver", "gray"], (4, 7)),
    ("charger", "handheld mini fan, folded", ["white", "pink", "mint"], (12, 18)),
    # 기타
    ("misc", "ballpoint pen", ["black", "blue", "metal", "click pen"], (13, 15)),
    ("misc", "small pocket notebook", ["black", "kraft brown", "pastel"], (10, 15)),
    ("misc", "pack of chewing gum", ["mint green", "blue", "white"], (7, 9)),
    ("misc", "lighter", ["red plastic", "black", "metal zippo-style"], (5, 8)),
    ("misc", "wooden name stamp seal (dojang)", ["round wooden", "with a cap"], (5, 7)),
    ("misc", "coins scattered", ["three coins", "five coins"], (3, 7)),
    ("misc", "ring and bracelet", ["silver", "gold", "beaded bracelet"], (2, 7)),
    ("misc", "small candy or snack bar", ["chocolate bar", "granola bar"], (9, 13)),
    ("bottle", "small water bottle", ["clear plastic", "stainless tumbler", "pastel tumbler"], (15, 20)),
]

# 2차: 빠진 소지품 15장, 판에서 잘 안 보이는 어려운 버전(검정·투명·얇음·작음·반사 등) 30장
ITEMS_2 = [
    # 빠진 소지품
    ("misc", "electronic cigarette vape pod device", ["black", "silver", "pastel blue", "pink"], (8, 11), 15),
    ("misc", "heated tobacco device", ["black", "white", "navy"], (9, 12), 15),
    ("misc", "cigarette pack", ["white", "dark blue", "silver"], (8, 9), 15),
    ("key", "round bluetooth item tracker tag", ["white disc", "white disc in a leather keyring holder", "black square tag"], (3, 6), 15),
    ("watch", "smart ring", ["matte black", "silver", "gold"], (2, 2.5), 15),
    ("misc", "phone stylus pen", ["black", "white", "lavender"], (10, 14), 15),
    ("card", "car parking access card", ["white", "gray", "with a cartoon print"], (8.5, 8.6), 15),
    ("card", "folded paper receipt", ["crumpled", "folded in half", "long thermal receipt"], (6, 12), 15),
    ("toiletry", "bobby pins and hair pins", ["black", "gold", "pearl hair pin"], (4, 7), 15),
    ("audio", "single wireless earbud", ["white with stem", "black round", "white round"], (2, 3.5), 15),
    ("misc", "small candy or jelly pouch", ["colorful", "pink", "green"], (8, 14), 15),
    ("misc", "disposable hand warmer pack", ["white", "printed orange"], (9, 13), 15),
    ("misc", "folded compact mini umbrella", ["black", "navy", "beige", "pink"], (15, 25), 15),
    ("key", "car smart key in a leather key case", ["black leather", "brown leather", "pink leather"], (7, 10), 15),
    ("phone", "phone ring grip holder, detached", ["black", "clear", "character print"], (4, 5), 15),
    # 어려운 버전 — 판(진회색 · 검정)과 같은 색
    ("key", "car smart key fob", ["matte black", "glossy black", "dark gray"], (6, 9), 30),
    ("audio", "wireless earbuds charging case, closed", ["matte black", "dark graphite gray"], (5, 7), 30),
    ("wallet", "bifold leather wallet", ["matte black", "dark charcoal"], (9, 12), 30),
    ("phone", "smartphone lying face down", ["matte black", "dark graphite"], (14, 17), 30),
    ("eyewear", "folded eyeglasses", ["matte black thick frames", "thin black frames"], (13, 15), 30),
    ("charger", "USB-C wall charger brick with folding plug", ["matte black", "dark gray"], (4, 7), 30),
    ("charger", "portable power bank", ["matte black", "dark gray"], (9, 15), 30),
    ("tissue", "folded disposable face mask", ["black KF94", "dark gray"], (11, 18), 30),
    # 투명
    ("phone", "smartphone in a clear transparent case, back side", ["black phone", "white phone", "blue phone"], (14, 17), 30),
    ("card", "empty clear plastic ID badge holder", ["rigid", "soft vinyl"], (9, 12), 30),
    ("toiletry", "clear transparent lip gloss or lip balm tube", ["clear", "pink tint"], (6, 9), 30),
    ("bottle", "small clear plastic water bottle", ["with blue cap", "with white cap", "half empty"], (15, 20), 30),
    # 얇고 납작
    ("card", "plain plastic card", ["white", "light gray", "black", "silver"], (8.5, 8.6), 30),
    ("card", "employee ID badge card without a holder", ["white with blue stripe", "white with photo"], (8.5, 8.6), 30),
    ("tissue", "flat folded paper tissue", ["white"], (10, 12), 30),
    # 가늘고 긺
    ("charger", "loose USB cable lying in a loose curve", ["white", "black", "braided gray"], (15, 25), 30),
    ("audio", "wired earphones with a tangled cable", ["white", "black"], (10, 18), 30),
    ("toiletry", "elastic hair tie", ["black", "brown", "colorful"], (4, 6), 30),
    # 아주 작음
    ("key", "small RFID door key tag without keyring", ["blue", "black", "gray"], (3, 4.5), 30),
    ("charger", "tiny USB-C flash drive", ["silver", "black"], (2.5, 4), 30),
    ("misc", "single coin", ["silver 500 won", "copper 10 won"], (2, 2.7), 30),
    ("misc", "single plain ring", ["silver", "gold", "black"], (2, 2.3), 30),
    # 금속 반사
    ("watch", "analog wristwatch with a polished metal bracelet", ["polished silver", "polished gold"], (17, 22), 30),
    ("key", "shiny metal house keys on a ring", ["two keys", "four keys"], (6, 10), 30),
    ("wallet", "metal aluminum card holder", ["silver", "black anodized"], (9, 10), 30),
    # 열린 · 펼친 상태
    ("audio", "wireless earbuds charging case with lid open and earbuds inside", ["white", "black"], (5, 7), 30),
    ("wallet", "bifold wallet lying open flat", ["black", "brown"], (18, 22), 30),
    ("eyewear", "eyeglasses lying with temples open", ["black", "tortoiseshell", "metal"], (13, 15), 30),
    # 연결된 상태
    ("key", "keyring with car key, house keys and a small charm", ["black car key", "silver car key"], (10, 14), 30),
    ("charger", "phone charger with a cable plugged in, cable coiled", ["white", "black"], (12, 20), 30),
]

BACKGROUNDS = ["plain white", "light gray", "plain off-white"]   # 오리기 쉬운 단색 바탕


def prompt(noun, variant, bg):
    return (f"Top-down overhead flat lay photo of a single {variant} {noun}, lying flat, centered, small in the frame, "
            f"entire object fully visible with wide empty margin on all sides, on a {bg} seamless background, soft diffuse daylight, "
            f"realistic smartphone photo, sharp focus, no other objects, no hands, no text")
