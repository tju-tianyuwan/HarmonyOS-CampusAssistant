import unittest

from app.services.mas import (
    MAS_AGENTS,
    build_agent_system,
    build_agent_user,
    public_agents,
    role_for_agent,
    select_agents,
)


class MasOrchestrationTest(unittest.TestCase):
    def test_default_roster_has_distinct_course_discussion_roles(self) -> None:
        agents = public_agents()

        self.assertEqual(len(agents), 4)
        self.assertEqual(len({agent["id"] for agent in agents}), 4)
        self.assertEqual(len({agent["personality"] for agent in agents}), 4)
        self.assertTrue(all(agent["name"] and agent["title"] for agent in agents))

    def test_selection_keeps_three_to_five_valid_agents(self) -> None:
        fallback = select_agents(["analyst"])
        selected = select_agents(["synthesizer", "analyst", "missing", "skeptic"])

        self.assertEqual(len(fallback), 3)
        self.assertEqual([agent.id for agent in selected], ["analyst", "skeptic", "synthesizer"])

    def test_agent_prompt_contains_personality_context_and_prior_views(self) -> None:
        agent = MAS_AGENTS[1]
        system = build_agent_system(
            agent,
            "中序遍历顺序是左子树、根节点、右子树。",
            "学生上一轮在比较前序和中序遍历。",
            True,
        )
        user = build_agent_user(
            "为什么二叉搜索树中序遍历有序？",
            [("小研", "因为左子树小于根节点，右子树大于根节点。")],
        )

        self.assertIn("[MAS_AGENT:skeptic]", system)
        self.assertIn(agent.personality, system)
        self.assertIn("课程知识库片段", system)
        self.assertIn("小研", user)
        self.assertIn("为什么二叉搜索树", user)
        self.assertEqual(role_for_agent(agent), "assistant:skeptic")


if __name__ == "__main__":
    unittest.main()
