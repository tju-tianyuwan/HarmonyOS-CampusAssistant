import json
import unittest

from app.services.practice import PracticeGenerationError, parse_questions


class PracticeParserTest(unittest.TestCase):
    def test_parses_fenced_questions_and_restricts_sources(self) -> None:
        raw = "```json\n" + json.dumps(
            {
                "questions": [
                    {
                        "type": "单选题",
                        "difficulty": "基础",
                        "topic": "二叉树",
                        "stem": "中序遍历的访问顺序是？",
                        "options": ["根左右", "左根右", "左右根", "层序"],
                        "answer": "B",
                        "explanation": "中序遍历遵循左子树、根节点、右子树。",
                        "source": "模型伪造来源",
                    }
                ]
            },
            ensure_ascii=False,
        ) + "\n```"

        questions = parse_questions(raw, 1, "综合", "适中", ["第5讲 二叉树"])

        self.assertEqual(questions[0]["answer"], 1)
        self.assertEqual(questions[0]["source"], "第5讲 二叉树")
        self.assertEqual(questions[0]["id"], 1)

    def test_rejects_invalid_option_count(self) -> None:
        raw = json.dumps(
            {
                "questions": [
                    {
                        "stem": "题干",
                        "options": ["A", "B", "C"],
                        "answer": 0,
                        "explanation": "解析",
                    }
                ]
            },
            ensure_ascii=False,
        )

        with self.assertRaises(PracticeGenerationError):
            parse_questions(raw, 1, "综合", "适中", ["课程知识库"])


if __name__ == "__main__":
    unittest.main()
