<?php

declare(strict_types=1);

return [
    'dsn' => getenv('DB_DSN') ?: 'mysql:host=localhost;port=3306;dbname=hm491715_testingaq;charset=utf8mb4',
    'user' => getenv('DB_USER') ?: 'hm491715_testinaq',
    'password' => getenv('DB_PASSWORD') ?: 'uW1aY7aL1Y',
];
