# Playground documentation

Documentation follows Diátaxis, separating learning, practical tasks, technical reference, and explanation.

Start with the tutorial if this is your first visit. Otherwise, follow the branch that matches your goal. Click a document in the diagram to open it, or use the links in the table below.

```mermaid
flowchart TD
    Start{"What do you need?"}
    Start -->|Get started| Tutorial["Tutorial: Create your first five-VM network"]
    Start -->|Complete a task| Task{"Which task?"}
    Start -->|Look something up| Reference{"Which details?"}
    Start -->|Understand the design| Architecture["Explanation: Network architecture and K3s"]

    Task -->|Manage VMs or install K3s| Manage["How-to: Manage playgrounds and K3s"]
    Task -->|Fix a problem| Troubleshoot["How-to: Troubleshoot playgrounds"]
    Task -->|Check script changes| Validate["How-to: Validate script changes"]

    Reference -->|Compare VM layouts| Setups["Reference: Setup specifications"]
    Reference -->|Check commands or output| Commands["Reference: Commands and execution output"]

    click Tutorial "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/tutorials/first-playground.md"
    click Manage "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/how-to/manage-playgrounds.md"
    click Troubleshoot "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/how-to/troubleshoot.md"
    click Validate "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/how-to/validate-scripts.md"
    click Setups "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/reference/setups.md"
    click Commands "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/reference/commands.md"
    click Architecture "https://github.com/iamunnip/iximiuz-labs/blob/main/docs/explanation/architecture.md"
```

| Section | Purpose | Start here |
| --- | --- | --- |
| Tutorials | Learn by completing a guided exercise | [Create your first five-VM network](tutorials/first-playground.md) |
| How-to guides | Complete a specific task | [Manage playgrounds and K3s](how-to/manage-playgrounds.md), [troubleshoot](how-to/troubleshoot.md), [validate scripts](how-to/validate-scripts.md) |
| Reference | Look up specifications and command behavior | [Setups](reference/setups.md), [commands and execution output](reference/commands.md) |
| Explanation | Understand the design | [Network architecture and K3s](explanation/architecture.md) |

Both setups manage the playground titles `node-01` through `node-05`. Use one setup at a time per account.
