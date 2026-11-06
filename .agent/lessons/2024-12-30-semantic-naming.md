# 2024-12-30: The Value of Semantic Directories

## The Event

We initially had `home/` for user configs and `modules/home-manager/` for default user logic.

## The Friction

It was confusing to talk about "home modules" vs "home configs". The AI (me) had to pause and clarify intent.

## The Lesson

**Semantic Naming > Technical Naming.**
Renaming `home/` to `users/` instantly clarified the architecture.

- `modules/` = Code
- `users/` = Humans
- `hosts/` = Machines

## Action Item

Always question directory names that require a "double take".
