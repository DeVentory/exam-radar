"""문제은행 검사: 필수 필드, id 중복, 핵심 용어(kw)가 정답(a) 안에 실제로 있는지.

    python3 tools/check_questions.py Resources/questions.json

kw의 "A|B"는 같은 뜻의 대안이다. 첫 번째(A)는 정답 문장 안에 있어야 한다.
"""
import json, re, sys


def norm(s):
    return re.sub(r"[\s·,.()（）]", "", s).lower()


path = sys.argv[1]
qs = json.load(open(path, encoding="utf-8"))
errors, ids = [], set()
for q in qs:
    for f in ("id", "ch", "p", "q", "a"):
        if not q.get(f):
            errors.append(f"{q.get('id', '?')}: '{f}' 없음")
    if q.get("id") in ids:
        errors.append(f"{q['id']}: id 중복")
    ids.add(q.get("id"))
    for k in q.get("kw", []):
        if norm(k.split("|")[0]) not in norm(q.get("a", "")):
            errors.append(f"{q['id']}: 핵심 용어 '{k}'가 정답에 없음")
if errors:
    print("\n".join("❌ " + e for e in errors))
    sys.exit(1)
print(f"✅ 문제은행 {len(qs)}문항, 핵심 용어 {sum(len(q.get('kw', [])) for q in qs)}개 확인")
