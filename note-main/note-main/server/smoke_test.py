"""Demo 全链路冒烟测试。

用法：
  1. 启动服务端: .venv/Scripts/python -m uvicorn app.main:app --port 8000
  2. 另开终端:   .venv/Scripts/python smoke_test.py

覆盖：健康检查 → 预置账号 → 建集合/加入 → 录音分片转写 → 提纲生成 →
教师发布入库 → 集合限定问答（SSE+引用来源）→ 跨集合隔离 → 笔记共享质量评估。
"""
import json
import sys

import httpx

sys.stdout.reconfigure(encoding="utf-8")  # Windows 控制台默认 GBK，强制 UTF-8 防中文乱码

BASE = "http://127.0.0.1:8000"
API = BASE + "/api/v1"

passed: list[str] = []
failed: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    (passed if cond else failed).append(name)
    print(("[PASS]" if cond else "[FAIL]"), name, "|", detail)


def sse_collect(resp: httpx.Response) -> tuple[list, str]:
    """解析 SSE：返回 (引用来源, 完整回答文本)"""
    sources: list = []
    text = ""
    event = None
    for line in resp.iter_lines():
        if line.startswith("event:"):
            event = line.split(":", 1)[1].strip()
        elif line.startswith("data:"):
            data = line.split(":", 1)[1].strip()
            if event == "sources":
                sources = json.loads(data)
                event = None
            elif event == "done":
                break
            else:
                try:
                    text += json.loads(data)
                except json.JSONDecodeError:
                    pass
    return sources, text


def main() -> None:
    with httpx.Client(timeout=120) as c:
        r = c.get(BASE + "/health")
        check("健康检查", r.status_code == 200, r.text)

        users = c.get(API + "/auth/users").json()
        teacher = next(u for u in users if u["role"] == "teacher")
        student = next(u for u in users if u["role"] == "student")
        check("预置账号", len(users) >= 3, f"教师={teacher['name']} 学生={student['name']}")

        cc = c.post(API + "/courses", json={
            "name": "冒烟测试课", "class_name": "测试班", "teacher_id": teacher["id"],
        }).json()
        check("教师创建课程集合", "id" in cc, f"id={cc.get('id')} 邀请码={cc.get('invite_code')}")
        ccid = cc["id"]

        j = c.post(API + "/courses/join", json={
            "user_id": student["id"], "invite_code": cc["invite_code"],
        }).json()
        check("学生凭邀请码加入", j.get("id") == ccid, "")

        s = c.post(API + "/sessions", json={
            "class_course_id": ccid, "title": "测试课时", "creator_id": teacher["id"],
        }).json()
        sid = s["id"]
        for seq in range(3):
            c.post(API + f"/sessions/{sid}/chunks/{seq}", files={"file": ("chunk.pcm", b"\x00" * 16)})
        tr = c.get(API + f"/sessions/{sid}/transcript").json()
        check("音频分片上传→ASR转写", len(tr) == 3, f"{len(tr)} 段，首段: {tr[0]['text'][:18]}…")
        c.post(API + f"/sessions/{sid}/finish")

        o = c.post(API + f"/sessions/{sid}/outline/generate").json()
        check("AI 生成 Markdown 提纲", o.get("status") == "draft" and bool(o.get("markdown")),
              f"{len(o.get('markdown', ''))} 字符")

        o2 = c.post(API + f"/sessions/{sid}/outline/review", json={
            "user_id": teacher["id"], "action": "publish",
        }).json()
        check("教师审核发布→写入知识库", o2.get("status") == "published", "")

        ch = c.post(API + "/chat/sessions", json={
            "class_course_id": ccid, "user_id": student["id"], "title": "测试会话",
        }).json()
        with c.stream("POST", API + "/chat/ask", json={
            "chat_session_id": ch["id"], "question": "二叉树的中序遍历顺序是什么？",
        }) as r:
            sources, text = sse_collect(r)
        check("集合限定问答(流式+来源)", bool(sources) and bool(text),
              f"来源={sources} 回答={text[:24]}…")

        cc_b = c.post(API + "/courses", json={
            "name": "隔离对照课", "class_name": "测试班", "teacher_id": teacher["id"],
        }).json()
        ch_b = c.post(API + "/chat/sessions", json={
            "class_course_id": cc_b["id"], "user_id": teacher["id"], "title": "隔离",
        }).json()
        with c.stream("POST", API + "/chat/ask", json={
            "chat_session_id": ch_b["id"], "question": "二叉树的中序遍历顺序是什么？",
        }) as r:
            src_b, text_b = sse_collect(r)
        check("知识库跨集合隔离", "未找到" in text_b and not src_b, f"对照集合回答={text_b}")

        n = c.post(API + "/notes", json={
            "class_course_id": ccid, "owner_id": student["id"], "title": "遍历总结", "kind": "md",
            "content": "# 二叉树遍历\n- 前序：根左右\n- 中序：左根右\n- 后序：左右根",
        }).json()
        n2 = c.post(API + f"/notes/{n['id']}/share").json()
        check("笔记共享→LLM质量评估", n2.get("quality_status") in ("accepted", "rejected"),
              f"结果={n2.get('quality_status')} 得分={n2.get('quality_score')}")

    print(f"\n共 {len(passed)} 通过, {len(failed)} 失败" + (f": {failed}" if failed else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
