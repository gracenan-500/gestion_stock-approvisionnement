<?php

class Database
{
    private $host = "localhost";
    private $port = "5432";
    private $dbname = "gestion_stock";
    private $user = "postgres";
    private $password = "postgres";

    private $connexion;

    public function getConnexion()
    {e
        if ($this->connexion === null) {
            try {
                $this->connexion = new PDO(
                    "pgsql:host={$this->host};port={$this->port};dbname={$this->dbname}",
                    $this->user,
                    $this->password
                );

                $this->connexion->setAttribute(
                    PDO::ATTR_ERRMODE,
                    PDO::ERRMODE_EXCEPTION
                );

            } catch (PDOException $e) {
                die("Erreur connexion : " . $e->getMessage());
            }
        }

        return $this->connexion;
    }
}