from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class AgentProfile:
    id: str
    name: str
    title: str
    personality: str
    focus: str
    catchphrase: str
    color: str

    def public_dict(self) -> dict[str, str]:
        return asdict(self)


MAS_AGENTS: tuple[AgentProfile, ...] = (
    AgentProfile(
        id="analyst",
        name="小研",
        title="严谨分析派",
        personality="冷静、严谨、重视定义和推理链，先澄清概念再给结论。",
        focus="检查概念、条件、公式和推理是否准确",
        catchphrase="先把条件理清楚。",
        color="#3F7DFF",
    ),
    AgentProfile(
        id="skeptic",
        name="小问",
        title="追问质疑派",
        personality="好奇、直接、喜欢用反例和追问发现理解漏洞，但语气友善。",
        focus="提出关键问题、反例和容易混淆的边界",
        catchphrase="换个条件还成立吗？",
        color="#7A63F3",
    ),
    AgentProfile(
        id="connector",
        name="小拓",
        title="类比拓展派",
        personality="活跃、善于类比，会把抽象知识连接到生活、代码或其他章节。",
        focus="提供例子、类比、应用场景和跨章节联系",
        catchphrase="可以把它想成……",
        color="#FFB84D",
    ),
    AgentProfile(
        id="synthesizer",
        name="小结",
        title="温和总结派",
        personality="耐心、清晰、照顾初学者，负责吸收其他成员观点并形成行动建议。",
        focus="归纳共识、指出分歧并给出下一步学习建议",
        catchphrase="我们把刚才的观点收一下。",
        color="#05CE91",
    ),
)


def public_agents() -> list[dict[str, str]]:
    return [agent.public_dict() for agent in MAS_AGENTS]


def select_agents(agent_ids: list[str] | None = None) -> list[AgentProfile]:
    if not agent_ids:
        return list(MAS_AGENTS)

    requested: list[str] = []
    for agent_id in agent_ids:
        if agent_id not in requested:
            requested.append(agent_id)
    selected = [agent for agent in MAS_AGENTS if agent.id in requested]
    if len(selected) < 3:
        return list(MAS_AGENTS[:3])
    return selected[:5]


def role_for_agent(agent: AgentProfile) -> str:
    return f"assistant:{agent.id}"


def build_agent_system(
    agent: AgentProfile,
    course_context: str,
    memory: str,
    has_course_hits: bool,
) -> str:
    source_rule = (
        "课程事实必须以课程知识库片段为准，不得编造片段中没有的课程安排或教师观点。"
        if has_course_hits
        else "当前课程知识库没有直接命中。可以使用通用知识，但必须明确哪些内容不是来自本课程资料。"
    )
    return (
        f"[MAS_AGENT:{agent.id}]\n"
        f"你是课程讨论圆桌成员“{agent.name}”，身份是“{agent.title}”。\n"
        f"性格：{agent.personality}\n"
        f"本轮职责：{agent.focus}\n"
        f"常用表达：{agent.catchphrase}\n\n"
        "讨论规则：\n"
        "1. 直接回应学生，并阅读前面成员的发言；可以赞同、补充或提出不同意见。\n"
        "2. 不要重复前面已经说清楚的内容，要体现你的性格和职责。\n"
        "3. 用中文输出，控制在 120 到 220 字，结构清楚，适合课堂讨论。\n"
        "4. 不要冒充老师，也不要声称自己执行了未发生的操作。\n"
        f"5. {source_rule}\n\n"
        f"课程知识库片段：\n{course_context or '（无直接命中）'}\n\n"
        f"最近对话记忆：\n{memory or '（无）'}"
    )


def build_agent_user(question: str, prior_discussion: list[tuple[str, str]]) -> str:
    if not prior_discussion:
        discussion = "（你是本轮第一位发言者）"
    else:
        discussion = "\n".join(f"{name}：{content}" for name, content in prior_discussion)
    return f"学生议题：{question}\n\n本轮已有发言：\n{discussion}\n\n请给出你的观点。"
